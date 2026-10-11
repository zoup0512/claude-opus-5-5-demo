#!/usr/bin/env python3
"""一键部署到飞牛 NAS（192.168.110.140）：
- 静态站点 → /vol1/docker/pelican-bike（nginx:alpine 容器 :8091）
- 对战服务器 → /vol1/docker/pelican-bike-server（node:22-alpine 容器，仅内部网络）
- nginx 增加 /ws 反向代理（docker network pelican-net 内部解析）
用法：python deploy.py [--host 192.168.110.140] [--user root] [--pass 密码或 PELICAN_NAS_PASS 环境变量]
"""
import argparse
import os
import posixpath
import sys

import paramiko

HERE = os.path.dirname(os.path.abspath(__file__))
STATIC_DIR = "/vol1/docker/pelican-bike"
SERVER_DIR = "/vol1/docker/pelican-bike-server"
WS_LIB = os.path.join(HERE, "node_modules", "ws")


def mkdirs(sftp, remote_dir):
    cur = ""
    for p in remote_dir.strip("/").split("/"):
        cur += f"/{p}"
        try:
            sftp.stat(cur)
        except FileNotFoundError:
            sftp.mkdir(cur)


def put(sftp, local, remote):
    mkdirs(sftp, posixpath.dirname(remote))
    sftp.put(os.path.join(HERE, local), remote)
    print(f"  {local} → {remote}")


def upload_tree(sftp, local_dir, remote_dir):
    count = 0
    for root, _dirs, files in os.walk(local_dir):
        rel = os.path.relpath(root, local_dir).replace("\\", "/")
        rdir = remote_dir if rel == "." else f"{remote_dir}/{rel}"
        mkdirs(sftp, rdir)
        for f in files:
            if f.endswith((".md", ".DS_Store", ".npmignore", ".DS_Store")) or f.startswith("."):
                continue
            sftp.put(os.path.join(root, f), posixpath.join(rdir, f))
            count += 1
    return count


def run(c, cmd, timeout=240):
    _, out, err = c.exec_command(cmd, timeout=timeout)
    o, e = out.read().decode().strip(), err.read().decode().strip()
    return (o or e).replace("\n", "\n  ")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="192.168.110.140")
    ap.add_argument("--user", default="root")
    ap.add_argument("--pass", dest="password", default=os.environ.get("PELICAN_NAS_PASS"))
    args = ap.parse_args()
    if not args.password:
        sys.exit("需要 NAS SSH 密码：--pass 或环境变量 PELICAN_NAS_PASS")

    os.chdir(HERE)
    if not os.path.isfile("dist/index.html"):
        sys.exit("先运行 node build.mjs")

    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(args.host, username=args.user, password=args.password, timeout=10)
    sftp = c.open_sftp()

    print("[1/5] 上传静态页与服务器代码…")
    put(sftp, "dist/index.html", f"{STATIC_DIR}/index.html")
    put(sftp, "deploy/nginx.conf", f"{STATIC_DIR}/nginx.conf")
    put(sftp, "server/index.mjs", f"{SERVER_DIR}/server/index.mjs")
    put(sftp, "server/room.mjs", f"{SERVER_DIR}/server/room.mjs")
    put(sftp, "server/match.mjs", f"{SERVER_DIR}/server/match.mjs")
    put(sftp, "shared/protocol.mjs", f"{SERVER_DIR}/shared/protocol.mjs")
    n = upload_tree(sftp, WS_LIB, f"{SERVER_DIR}/node_modules/ws")
    print(f"  node_modules/ws/* → {n} 个文件")
    sftp.close()

    print("[2/5] 准备 docker 网络…")
    print(" ", run(c, "docker network create pelican-net 2>/dev/null; echo net=$(docker network ls --filter name=pelican-net -q | wc -l)"))

    print("[3/5] 启动对战服务器容器…")
    print(" ", run(c, "docker rm -f pelican-bike-server 2>/dev/null; "
        "docker run -d --name pelican-bike-server --restart unless-stopped "
        f"--network pelican-net -e HOST=0.0.0.0 -v {SERVER_DIR}:/srv -w /srv node:22-alpine node server/index.mjs"))

    print("[4/5] 重建静态 nginx 容器（含 /ws 反代）…")
    print(" ", run(c, "docker rm -f pelican-bike 2>/dev/null; "
        "docker run -d --name pelican-bike --restart unless-stopped "
        "--network pelican-net -p 8091:80 "
        f"-v {STATIC_DIR}:/usr/share/nginx/html:ro "
        f"-v {STATIC_DIR}/nginx.conf:/etc/nginx/conf.d/default.conf:ro "
        "nginx:alpine"))

    print("[5/5] 健康检查…")
    print(" ", run(c, "sleep 2; docker ps --filter name=pelican --format '{{.Names}} {{.Status}}'"))
    print(" ", run(c, "curl -s -o /dev/null -w 'static:%{http_code}\\n' -m 5 http://127.0.0.1:8091/; "
        "docker exec pelican-bike curl -s -m 5 http://pelican-bike-server:8092/healthz; echo"))
    c.close()
    print(f"\n部署完成：http://{args.host}:8091/")


if __name__ == "__main__":
    main()
