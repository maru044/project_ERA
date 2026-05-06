import os
from PIL import Image

def batch_convert_to_webp(source_dir, target_dir, quality=85):
    """
    批量将指定文件夹中的 PNG 和 JPG 图像转换为 WebP 格式。
    
    参数:
    source_dir: 包含原始图像的文件夹路径
    target_dir: 保存转换后 WebP 图像的文件夹路径
    quality: WebP 图片压缩质量 (1-100, 推荐 85 作为画质和体积的平衡)
    """
    # 确保目标文件夹存在
    os.makedirs(target_dir, exist_ok=True)

    print(f"====================================")
    print(f" 开始执行批量 WebP 转换工具")
    print(f" 源文件夹: {os.path.abspath(source_dir)}")
    print(f" 目标文件夹: {os.path.abspath(target_dir)}")
    print(f"====================================\n")

    # 检查源文件夹是否存在
    if not os.path.exists(source_dir):
        print(f"[错误] 找不到源文件夹: {source_dir}。系统已为您自动创建该文件夹，请放入图片后重试。")
        os.makedirs(source_dir, exist_ok=True)
        return

    converted_count = 0
    skipped_count = 0

    # 遍历文件夹下的所有文件
    for filename in os.listdir(source_dir):
        # 仅处理 png, jpg, jpeg 格式的图片
        if filename.lower().endswith((".png", ".jpg", ".jpeg")):
            img_path = os.path.join(source_dir, filename)
            
            # 生成带 .webp 后缀的新文件名
            name_without_ext = os.path.splitext(filename)[0]
            webp_filename = f"{name_without_ext}.webp"
            webp_path = os.path.join(target_dir, webp_filename)
            
            try:
                # 使用 Pillow 打开图片并转换保存
                img = Image.open(img_path)
                # 如果是带透明通道的 RGBA 图片，直接保存为 WebP
                # lossless=False 代表开启有损压缩，能极大程度减少体积
                img.save(webp_path, "webp", quality=quality, lossless=False)
                
                # 计算压缩比
                original_size = os.path.getsize(img_path) / 1024 # KB
                new_size = os.path.getsize(webp_path) / 1024 # KB
                
                print(f"[成功] {filename} -> {webp_filename} (体积: {original_size:.1f}KB -> {new_size:.1f}KB)")
                converted_count += 1
            except Exception as e:
                print(f"[失败] 转换 {filename} 时发生错误: {e}")
                skipped_count += 1
        else:
            # 忽略非图片文件
            continue

    print(f"\n====================================")
    print(f" 转换完成！")
    print(f" 共成功转换: {converted_count} 张")
    print(f" 失败或跳过: {skipped_count} 张")
    print(f"====================================")

if __name__ == "__main__":
    # 配置默认路径 (这里设置为与脚本同级的两个文件夹)
    # 把要转换的图丢进 input_images 文件夹，运行脚本，就可以在 output_webp 文件夹里拿到压缩好的图了
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
    INPUT_DIR = os.path.join(SCRIPT_DIR, "input_images")
    OUTPUT_DIR = os.path.join(SCRIPT_DIR, "output_webp")
    
    batch_convert_to_webp(INPUT_DIR, OUTPUT_DIR, quality=85)
