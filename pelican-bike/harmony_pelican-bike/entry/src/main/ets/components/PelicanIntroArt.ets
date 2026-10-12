import { PelicanColors } from '../theme/PelicanTheme';

@Component
export struct PelicanIntroArt {
  widthValue: number = 300;
  heightValue: number = 190;
  contextSettings: RenderingContextSettings = new RenderingContextSettings(true);
  canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.contextSettings);
  phase: number = 0;
  timerId: number = -1;

  aboutToAppear(): void {
    this.startAnimation();
  }

  aboutToDisappear(): void {
    this.stopAnimation();
  }

  build() {
    Canvas(this.canvasContext)
      .width(this.widthValue)
      .height(this.heightValue)
      .onReady(() => {
        this.draw();
      })
      .shadow({ radius: 30, color: '#66000000', offsetX: 0, offsetY: 12 })
  }

  startAnimation(): void {
    this.stopAnimation();
    this.timerId = setInterval(() => {
      this.phase += 0.10;
      this.draw();
    }, 50);
  }

  stopAnimation(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  draw(): void {
    const context: CanvasRenderingContext2D = this.canvasContext;
    // Canvas drawing coordinates are in vp; ctx.width/height report the component
    // size directly (verified against working Canvas usage on this SDK).
    const canvasWidth: number = context.width;
    const canvasHeight: number = context.height;
    if (canvasWidth <= 0 || canvasHeight <= 0) {
      return;
    }
    const scaleX: number = canvasWidth / 300;
    const scaleY: number = canvasHeight / 190;
    context.reset();
    context.clearRect(0, 0, canvasWidth, canvasHeight);
    context.save();
    context.scale(scaleX, scaleY);
    this.drawRoad(context);
    this.drawWheel(context, 84, 140, 36, this.phase * 3.6);
    this.drawWheel(context, 210, 140, 36, this.phase * 3.6);
    this.drawBike(context);
    context.save();
    context.translate(0, Math.sin(this.phase * 2.0) * 2.0);
    this.drawPelican(context);
    context.restore();
    context.restore();
  }

  drawRoad(context: CanvasRenderingContext2D): void {
    context.save();
    context.strokeStyle = PelicanColors.ROAD;
    context.lineWidth = 3;
    context.setLineDash([18, 14]);
    context.lineDashOffset = -(this.phase * 32) % 32;
    context.beginPath();
    context.moveTo(0, 178);
    context.lineTo(300, 178);
    context.stroke();
    context.restore();
  }

  drawWheel(context: CanvasRenderingContext2D, centerX: number, centerY: number,
    radius: number, rotation: number): void {
    context.save();
    context.translate(centerX, centerY);
    context.rotate(rotation);
    context.strokeStyle = PelicanColors.CYAN;
    context.lineWidth = 5;
    context.beginPath();
    context.arc(0, 0, radius, 0, Math.PI * 2);
    context.stroke();
    context.strokeStyle = '#CCFFEE';
    context.lineWidth = 1.3;
    for (let index: number = 0; index < 8; index += 1) {
      const angle: number = index * Math.PI / 4;
      context.beginPath();
      context.moveTo(0, 0);
      context.lineTo(Math.cos(angle) * radius, Math.sin(angle) * radius);
      context.stroke();
    }
    context.restore();
  }

  drawBike(context: CanvasRenderingContext2D): void {
    context.save();
    context.strokeStyle = PelicanColors.CYAN_DARK;
    context.lineWidth = 6;
    context.lineJoin = 'round';
    context.lineCap = 'round';
    context.beginPath();
    context.moveTo(84, 140);
    context.lineTo(140, 142);
    context.lineTo(186, 98);
    context.lineTo(118, 98);
    context.closePath();
    context.moveTo(140, 142);
    context.lineTo(112, 84);
    context.moveTo(210, 140);
    context.lineTo(192, 80);
    context.lineTo(178, 78);
    context.stroke();
    context.strokeStyle = '#19181B';
    context.lineWidth = 5;
    context.beginPath();
    context.moveTo(104, 82);
    context.lineTo(129, 82);
    context.stroke();
    context.restore();
  }

  drawPelican(context: CanvasRenderingContext2D): void {
    context.save();
    context.fillStyle = '#F6F3EC';
    context.beginPath();
    context.ellipse(120, 70, 46, 30, -18 * Math.PI / 180, 0, Math.PI * 2);
    context.fill();

    context.strokeStyle = '#F6F3EC';
    context.lineWidth = 16;
    context.lineCap = 'round';
    context.beginPath();
    context.moveTo(150, 58);
    context.bezierCurveTo(170, 40, 150, 22, 166, 10);
    context.stroke();

    context.fillStyle = '#F6F3EC';
    context.beginPath();
    context.arc(168, 12, 13, 0, Math.PI * 2);
    context.fill();

    context.fillStyle = '#FF5A4E';
    context.beginPath();
    context.moveTo(172, 6);
    context.bezierCurveTo(150, -8, 150, -8, 140, 0);
    context.lineTo(172, 6);
    context.fill();

    context.fillStyle = '#F7C25C';
    context.beginPath();
    context.moveTo(176, 10);
    context.lineTo(262, 30);
    context.lineTo(178, 22);
    context.closePath();
    context.fill();

    context.fillStyle = '#E6F5B857';
    context.beginPath();
    context.moveTo(178, 22);
    context.quadraticCurveTo(220, 52, 256, 32);
    context.lineTo(262, 30);
    context.closePath();
    context.fill();

    context.fillStyle = '#1A0C08';
    context.beginPath();
    context.arc(170, 11, 2.6, 0, Math.PI * 2);
    context.fill();

    context.strokeStyle = '#19181B';
    context.lineWidth = 7;
    context.lineCap = 'round';
    context.beginPath();
    context.moveTo(100, 76);
    context.lineTo(150, 100);
    context.stroke();

    context.strokeStyle = '#F38A2A';
    context.lineWidth = 5;
    context.beginPath();
    context.moveTo(118, 92);
    context.lineTo(138, 142);
    context.stroke();

    context.strokeStyle = '#D7263D';
    context.lineWidth = 7;
    context.beginPath();
    context.moveTo(150, 50);
    context.bezierCurveTo(120, 40, 96, 58, 70, 50);
    context.stroke();
    context.restore();
  }
}
