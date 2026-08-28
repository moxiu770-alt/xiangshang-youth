#!/usr/bin/env python3
"""Generate a print-at-100% ChArUco board and floor-placement kit.

This is a physical setup aid for the posture-capture protocol. It does not
make the current mobile client Marker-PnP capable: an approved native detector
and per-device camera calibration are still required before a profile can be
activated. No child data is created or processed.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

mm = 72.0 / 25.4


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "output/pdf/xiangshang-youth-physical-capture-kit-v1.pdf"
ASSET = ROOT / "tmp/capture-kit-assets/uy-charuco-floor-wall-v1.png"

SPEC = {
    "boardId": "uy-charuco-floor-wall-v1",
    "boardFamily": "charuco",
    "dictionary": "DICT_4X4_50",
    "squaresX": 7,
    "squaresY": 10,
    "squareLengthMm": 24,
    "markerLengthMm": 17,
    "boardWidthMm": 168,
    "boardHeightMm": 240,
    "printDpi": 300,
}
LAYOUT_HASH = hashlib.sha256(json.dumps(SPEC, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def font_name() -> str:
    candidate = Path("/System/Library/Fonts/Supplemental/Songti.ttc")
    if candidate.is_file():
        try:
            pdfmetrics.registerFont(TTFont("Songti", str(candidate), subfontIndex=0))
            return "Songti"
        except Exception:
            pass
    return "Helvetica"


def make_board() -> None:
    # OpenCV is intentionally imported only for board rendering. This lets the
    # PDF step use the bundled document runtime even when it lacks cv2.
    import cv2
    ASSET.parent.mkdir(parents=True, exist_ok=True)
    pixels_per_mm = SPEC["printDpi"] / 25.4
    size = (round(SPEC["boardWidthMm"] * pixels_per_mm), round(SPEC["boardHeightMm"] * pixels_per_mm))
    dictionary = cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50)
    board = cv2.aruco.CharucoBoard((SPEC["squaresX"], SPEC["squaresY"]), SPEC["squareLengthMm"], SPEC["markerLengthMm"], dictionary)
    image = board.generateImage(size, marginSize=0, borderBits=1)
    if not cv2.imwrite(str(ASSET), image):
        raise RuntimeError("无法写入 ChArUco 标定板图像")


def text(canvas: Canvas, content: str, x: float, y: float, size: float, font: str, color=None) -> None:
    canvas.setFont(font, size)
    canvas.setFillColor(color or HexColor("#13213D"))
    canvas.drawString(x, y, content)


def line(canvas: Canvas, content: str, x: float, y: float, max_width: float, size: float, font: str, leading: float | None = None) -> float:
    leading = leading or size * 1.5
    words = list(content)
    row = ""
    for word in words:
        candidate = row + word
        if row and canvas.stringWidth(candidate, font, size) > max_width:
            text(canvas, row, x, y, size, font)
            y -= leading
            row = word
        else:
            row = candidate
    if row:
        text(canvas, row, x, y, size, font)
        y -= leading
    return y


def draw_pdf() -> None:
    global Color, HexColor, Canvas, pdfmetrics, TTFont
    from reportlab.lib.colors import Color, HexColor
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    from reportlab.pdfgen.canvas import Canvas
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    font = font_name()
    canvas = Canvas(str(OUTPUT), pagesize=(210 * mm, 297 * mm), pageCompression=1)
    page_w, page_h = 210 * mm, 297 * mm

    # Page 1: actual marker board, placed at exact physical size.
    canvas.setFillColor(Color(1, 1, 1)); canvas.rect(0, 0, page_w, page_h, fill=1, stroke=0)
    board_w, board_h = SPEC["boardWidthMm"] * mm, SPEC["boardHeightMm"] * mm
    board_x, board_y = (page_w - board_w) / 2, 28 * mm
    canvas.drawImage(str(ASSET), board_x, board_y, width=board_w, height=board_h, preserveAspectRatio=False, mask='auto')
    canvas.setStrokeColor(HexColor("#16A67A")); canvas.setLineWidth(.7); canvas.rect(board_x, board_y, board_w, board_h, fill=0, stroke=1)
    text(canvas, "向上少年 - 物理标定板", 16 * mm, page_h - 14 * mm, 10, font)
    text(canvas, "UY-CAPTURE-MARKER-PNP-1.0 | 必须 100% 原尺寸打印，禁止适应页面或缩放", 16 * mm, page_h - 20 * mm, 6.6, font, HexColor("#55627A"))
    text(canvas, f"ID {SPEC['boardId']} | ChArUco 4x4_50 | 7 x 10 | 方格 24 mm | Marker 17 mm", 16 * mm, 17 * mm, 6.3, font, HexColor("#55627A"))
    text(canvas, f"版式 SHA-256 {LAYOUT_HASH}", 16 * mm, 11 * mm, 5.8, font, HexColor("#55627A"))
    canvas.showPage()

    # Page 2: placement/checklist. It is intentionally not an ArUco target.
    canvas.setFillColor(Color(1, 1, 1)); canvas.rect(0, 0, page_w, page_h, fill=1, stroke=0)
    canvas.setFillColor(HexColor("#EFF9F5")); canvas.roundRect(12 * mm, page_h - 58 * mm, page_w - 24 * mm, 42 * mm, 6 * mm, fill=1, stroke=0)
    text(canvas, "L 形物理标定区 - 现场布置卡", 20 * mm, page_h - 29 * mm, 17, font)
    line(canvas, "此页用于现场摆位和验收，不参与图像检测。结果只在后置 1x、实体标定板检测、PnP 误差和设备内参均通过后才能使用标定级标签。", 20 * mm, page_h - 39 * mm, page_w - 40 * mm, 8.4, font)
    y = page_h - 72 * mm
    sections = [
        ("一、安装", "将第 1 页贴在垂直硬质背板上，保持平整无反光；底边距地面 30-50 cm。地面足印垫与背板形成 90° L 形区域，主摄像头固定在三脚架上，镜头中心对准板中心。"),
        ("二、打印验收", "使用尺子实测任意三个棋盘格边长，应为 24.0 mm，误差不超过 0.3 mm；实测 Marker 黑边应为 17.0 mm。未通过时重新以 100% 原尺寸打印，禁止照片翻拍或屏幕显示。"),
        ("三、手机与机位", "只允许后置 1x 主摄，关闭超广角、数码变焦、美颜与自动构图。冻结手机型号、镜头、分辨率和支架位置；采集前调平手机，检查全身完整入镜、单人、光线均匀和无明显遮挡。"),
        ("四、配置审批", "为每个 手机型号 + 后置 1x + 分辨率 单独取得内参矩阵与畸变系数，录入 approved profile。profile 必须包含本板 ID、版式 SHA-256、尺寸、内参、畸变参数、批准日期和失效日期。"),
        ("五、隐私与复核", "原始照片和视频只可在设备内存中临时用于识别，不上传、不进入报告。上传仅限质量分、PnP 重投影误差、结构化姿态指标和 profileId。每项完成两次独立入镜采集；不一致应重拍。"),
    ]
    for title, body in sections:
        text(canvas, title, 18 * mm, y, 11, font, HexColor("#0E755A")); y -= 7 * mm
        y = line(canvas, body, 18 * mm, y, page_w - 36 * mm, 8.2, font)
        y -= 5 * mm
    canvas.setFillColor(HexColor("#FFF4E8")); canvas.roundRect(14 * mm, 15 * mm, page_w - 28 * mm, 23 * mm, 5 * mm, fill=1, stroke=0)
    text(canvas, "验收签名：设备/镜头/分辨率 __________  标定人员 __________  日期 __________", 20 * mm, 28 * mm, 8, font)
    text(canvas, "不得以本卡、引导质量门或重复性测试替代人工标注验证、专业筛查或医疗诊断。", 20 * mm, 20 * mm, 7.2, font, HexColor("#8A4F10"))
    canvas.save()


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--board-only", action="store_true")
    parser.add_argument("--pdf-only", action="store_true")
    args = parser.parse_args()
    if not args.pdf_only:
        make_board()
    if not args.board_only:
        draw_pdf()
        print(OUTPUT)
