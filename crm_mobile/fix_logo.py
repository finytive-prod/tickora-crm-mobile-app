from PIL import Image

def process_image(input_path, output_path):
    img = Image.open(input_path).convert("RGBA")
    datas = img.getdata()

    newData = []
    for item in datas:
        # Check if the pixel is black or very dark grey
        if item[0] < 20 and item[1] < 20 and item[2] < 20:
            newData.append((255, 255, 255, 0)) # Transparent
        else:
            newData.append(item)

    img.putdata(newData)
    img.save(output_path, "PNG")

if __name__ == "__main__":
    process_image("assets/images/app_logo.jpg", "assets/images/app_logo.png")
    process_image("assets/images/splash_logo.jpg", "assets/images/splash_logo.png")
    print("Logos converted to PNG with transparent background.")
