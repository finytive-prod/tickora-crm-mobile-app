import os
from PIL import Image, ImageDraw, ImageFont

# 2. Load the original logo
logo_path = r"d:\CRM_MOBILE\tickora-crm-mobile-app\crm_mobile\assets\images\logo.png"
logo = Image.open(logo_path).convert("RGBA")

# Resize logo to fit inside the Android 12 safe zone
target_logo_size = 250
logo.thumbnail((target_logo_size, target_logo_size), Image.Resampling.LANCZOS)
logo_w, logo_h = logo.size

# Use a clean modern system font
font_options = [
    "C:/Windows/Fonts/segoeuib.ttf", # Segoe UI Bold
    "C:/Windows/Fonts/trebucbd.ttf", # Trebuchet MS Bold
    "C:/Windows/Fonts/arialbd.ttf"   # Arial Bold
]

font = None
for f in font_options:
    if os.path.exists(f):
        # Font size tuned to perfectly match the 250px logo
        font = ImageFont.truetype(f, 160)
        break

if font is None:
    font = ImageFont.load_default()

text = "Tickora CRM"

# CRITICAL FIX: The canvas MUST be a perfect square for Android 12 
# otherwise the OS squashes and distorts the image.
canvas_size = 2048
canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
draw = ImageDraw.Draw(canvas)

bbox = draw.textbbox((0, 0), text, font=font)
text_w = bbox[2] - bbox[0]
text_h = bbox[3] - bbox[1]

# Layout math
gap = 50 
total_w = logo_w + gap + text_w

# Center the whole group perfectly on the square canvas
start_x = (canvas_size - total_w) // 2
logo_y = (canvas_size - logo_h) // 2
text_y = (canvas_size - text_h) // 2 - 35 # optical center adjustment for baseline

# Paste logo and draw text
canvas.paste(logo, (start_x, logo_y), logo)
draw.text((start_x + logo_w + gap, text_y), text, font=font, fill=(255, 255, 255, 255))

# Save with maximum quality
out_path = r"d:\CRM_MOBILE\tickora-crm-mobile-app\crm_mobile\assets\images\splash_logo.png"
canvas.save(out_path, optimize=True)
print("Success")
