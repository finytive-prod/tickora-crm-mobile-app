from PIL import Image

def process_image(input_path, output_path):
    img = Image.open(input_path).convert("RGBA")
    img.save(output_path, "PNG")

if __name__ == "__main__":
    process_image("assets/images/logo.webp", "assets/images/logo.png")
    print("WebP converted to PNG.")
