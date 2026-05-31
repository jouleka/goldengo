#!/usr/bin/env python3
"""Generates a synthetic Raiffeisen-Albania-style PDF fixture with FAKE data only.
Each transaction is on its own line with enough vertical spacing for PDFKit line detection.
"""
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4
import os

out = os.path.join(os.path.dirname(__file__), "synthetic-statement.pdf")
c = canvas.Canvas(out, pagesize=A4)
lines = [
    "NXJERRJE LLOGARIE Dega Test",
    "DATA E TRANSAKSIONIT PERSHKRIMI DATE VALUTA DEBI KREDI BALANCA",
    "Balanca e Fillimit 1,000.00",
    "01/05/26 TEST MARKET 01/05/26 -100.00 900.00",
    "02/05/26 TEST SALARY 02/05/26 5,000.00 5,900.00",
    "Numri i veprimeve ne debi 1 -100.00",
]
y = 750
for ln in lines:
    c.drawString(40, y, ln)
    y -= 30   # 30pt gap so PDFKit sees them as separate lines
c.save()
print("wrote", out)
