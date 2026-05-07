import os
from PIL import Image, ImageOps

def resize_for_discord(source_path, target_width=1200, target_height=630, quality=85):
    """
    将过大的封面图裁剪并缩放为 Discord 最佳展示尺寸。
    
    参数:
    source_path: 原始大图的路径
    target_width: 目标宽度 (默认 1200)
    target_height: 目标高度 (默认 630)
    quality: 保存时的压缩质量
    """
    if not os.path.exists(source_path):
        print(f"[错误] 找不到文件: {source_path}")
        return

    try:
        img = Image.open(source_path)
        
        print(f"原始图片尺寸: {img.size[0]}x{img.size[1]}")
        
        # 使用 ImageOps.fit 进行智能裁剪与缩放
        # 它会以图片中心为基准，在不拉伸变形的前提下，填满 1200x630 的画幅，并切掉多余的边缘
        resized_img = ImageOps.fit(img, (target_width, target_height), method=Image.Resampling.LANCZOS, centering=(0.5, 0.5))
        
        # 生成输出路径，放在源文件同目录
        filename, ext = os.path.splitext(source_path)
        output_path = f"{filename}_discord_cover{ext}"
        
        # 如果是 RGBA (带透明度) 并且要存为 JPEG，需要转换为 RGB
        if img.mode in ("RGBA", "P") and ext.lower() in (".jpg", ".jpeg"):
            resized_img = resized_img.convert("RGB")
            
        resized_img.save(output_path, quality=quality)
        
        original_size = os.path.getsize(source_path) / 1024 / 1024 # MB
        new_size = os.path.getsize(output_path) / 1024 / 1024 # MB
        
        print(f"\n[成功] 封面已优化为 Discord 格式！")
        print(f"输出尺寸: {target_width}x{target_height}")
        print(f"文件大小: {original_size:.2f} MB -> {new_size:.2f} MB")
        print(f"保存路径: {output_path}")
        
    except Exception as e:
        print(f"[失败] 处理图片时发生错误: {e}")

if __name__ == "__main__":
    print("===========================================")
    print("      Discord 封面极速调整工具")
    print("===========================================\n")
    
    # 获取用户输入
    user_input = input("请输入您要处理的封面图片路径 (例如: C:\\images\\cover.png): \n> ").strip()
    
    # 去除路径两边的引号 (如果用户是直接拖拽文件进来的)
    if user_input.startswith('"') and user_input.endswith('"'):
        user_input = user_input[1:-1]
        
    # Discord 宣传贴 / Link Preview 的黄金比例通常是 1200x630
    resize_for_discord(user_input, 1200, 630)
    
    input("\n按回车键退出...")
