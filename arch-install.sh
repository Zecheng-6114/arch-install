#!/bin/bash

# Arch Linux 安装辅助脚本
# 作者：AI助手 | 版本：1.0 | 警告：请仔细阅读以下说明

set -e  # 任何命令失败即退出脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无色

# 显示带颜色的消息
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# =============== 配置区域（请根据实际情况修改） ===============
TARGET_DISK="/dev/sda"           # 目标磁盘（请用 lsblk 命令确认）
BOOT_PARTITION="${TARGET_DISK}1" # 引导分区
ROOT_PARTITION="${TARGET_DISK}2" # 根分区
HOSTNAME="archlinux"             # 主机名
TIMEZONE="Asia/Shanghai"         # 时区
LOCALE="en_US.UTF-8 UTF-8"       # 语言环境
KEYMAP="us"                      # 键盘布局
ROOT_PASSWORD="archlinux123"     # root密码（安装后请立即更改）
# =============== 配置结束 ===============

# 检查是否以root用户运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "此脚本必须以root权限运行"
        exit 1
    fi
}

# 检查网络连接
check_network() {
    info "检查网络连接..."
    if ! ping -c 3 archlinux.org &> /dev/null; then
        error "无法连接到网络，请先配置网络"
        exit 1
    fi
    info "网络连接正常"
}

# 检查启动模式
check_boot_mode() {
    if [[ -d /sys/firmware/efi/efivars ]]; then
        BOOT_MODE="UEFI"
    else
        BOOT_MODE="BIOS"
    fi
    info "检测到启动模式: $BOOT_MODE"
}

# 显示当前磁盘布局
show_disk_layout() {
    info "当前磁盘布局："
    lsblk -f
    warn "即将操作的目标磁盘: $TARGET_DISK"
    warn "此操作将清除 $TARGET_DISK 上的所有数据！"
    
    read -p "是否继续？(输入大写 YES 确认): " confirm
    if [[ "$confirm" != "YES" ]]; then
        info "操作已取消"
        exit 0
    fi
}

# 分区示例（根据启动模式）
partition_disk() {
    info "开始分区..."
    
    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        # UEFI模式分区方案
        warn "将创建以下分区："
        echo "- ${BOOT_PARTITION}: 512M EFI系统分区"
        echo "- ${ROOT_PARTITION}: 剩余空间作为根分区"
        
        # 这里显示命令，实际不自动执行（太危险）
        cat << EOF
        
请手动执行以下命令：

# 创建GPT分区表
parted $TARGET_DISK mklabel gpt

# 创建EFI分区
parted $TARGET_DISK mkpart primary fat32 1MiB 513MiB
parted $TARGET_DISK set 1 esp on

# 创建根分区
parted $TARGET_DISK mkpart primary ext4 513MiB 100%

# 格式化
mkfs.fat -F32 $BOOT_PARTITION
mkfs.ext4 $ROOT_PARTITION

EOF
        read -p "完成后按Enter键继续..."
    else
        # BIOS模式分区方案
        warn "将创建以下分区："
        echo "- ${ROOT_PARTITION}: 整个磁盘作为根分区"
        
        cat << EOF
        
请手动执行以下命令：

# 创建MBR分区表
parted $TARGET_DISK mklabel msdos

# 创建根分区
parted $TARGET_DISK mkpart primary ext4 1MiB 100%
parted $TARGET_DISK set 1 boot on

# 格式化
mkfs.ext4 $ROOT_PARTITION

EOF
        read -p "完成后按Enter键继续..."
    fi
}

# 挂载分区
mount_partitions() {
    info "挂载分区..."
    
    # 挂载根分区
    mount $ROOT_PARTITION /mnt
    
    # 如果是UEFI模式，创建并挂载EFI分区
    if [[ "$BOOT_MODE" == "UEFI" ]]; then
        mkdir -p /mnt/boot
        mount $BOOT_PARTITION /mnt/boot
    fi
    
    info "分区挂载完成"
}

# 选择镜像源（中国用户）
select_mirrors() {
    info "配置镜像源..."
    
    # 备份原镜像列表
    cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
    
    # 使用中国的镜像源（可根据需要修改）
    cat > /etc/pacman.d/mirrorlist << EOF
Server = https://mirrors.ustc.edu.cn/archlinux/\$repo/os/\$arch
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/\$repo/os/\$arch
Server = https://mirrors.bfsu.edu.cn/archlinux/\$repo/os/\$arch
EOF
    
    info "镜像源已更新"
}

# 安装基本系统
install_base() {
    info "开始安装基本系统..."
    
    # 安装基础包组
    pacstrap /mnt base base-devel linux linux-firmware
    
    # 安装常用工具
    arch-chroot /mnt pacman -S --noconfirm \
        networkmanager \
        vim \
        git \
        sudo \
        man-db \
        man-pages \
        texinfo
}

# 生成fstab
generate_fstab() {
    info "生成fstab文件..."
    genfstab -U /mnt >> /mnt/etc/fstab
    info "fstab已生成"
}

# 进入chroot环境进行系统配置
configure_system() {
    info "进入chroot环境配置系统..."
    
    # 复制此脚本到新系统以便继续执行
    cp "$0" /mnt/continue_install.sh
    chmod +x /mnt/continue_install.sh
    
    # chroot并执行配置
    arch-chroot /mnt /bin/bash << EOF
# 设置时区
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# 本地化设置
echo "$LOCALE" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# 键盘布局
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# 主机名
echo "$HOSTNAME" > /etc/hostname

# 设置root密码
echo "root:$ROOT_PASSWORD" | chpasswd

# 配置sudo（允许wheel组使用sudo）
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# 创建个人用户（可在此修改）
useradd -m -G wheel -s /bin/bash archuser
echo "archuser:archuser123" | chpasswd

# 安装引导程序
if [[ "$BOOT_MODE" == "UEFI" ]]; then
    pacman -S --noconfirm grub efibootmgr
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ARCH
else
    pacman -S --noconfirm grub
    grub-install --target=i386-pc $TARGET_DISK
fi
grub-mkconfig -o /boot/grub/grub.cfg

# 启用NetworkManager
systemctl enable NetworkManager

# 清理
rm /continue_install.sh
EOF
    
    info "系统配置完成"
}

# 显示安装完成信息
show_completion() {
    cat << EOF

${GREEN}===========================================
      Arch Linux 安装完成！
===========================================${NC}

基本配置：
- 主机名: $HOSTNAME
- 时区: $TIMEZONE
- 语言: en_US.UTF-8
- 用户: archuser (密码: archuser123)
- Root密码: $ROOT_PASSWORD

接下来请：
1. 退出chroot环境: exit
2. 卸载分区: umount -R /mnt
3. 重启系统: reboot
4. 登录后立即更改默认密码！

重要提醒：
1. 首次启动后运行: sudo pacman -Syu 更新系统
2. 安装显卡驱动：根据显卡类型安装相应驱动
3. 安装桌面环境（可选）：
   - GNOME: sudo pacman -S gnome gnome-extra
   - KDE: sudo pacman -S plasma-meta
   - XFCE: sudo pacman -S xfce4 xfce4-goodies

感谢使用此安装辅助脚本！
EOF
}

# 主执行流程
main() {
    clear
    cat << "EOF"
    ___                  _   _      _    
   / _ \ _ __ __ _ _   _| | | | ___| | __
  / /_)/ '__/ _` | | | | |_| |/ _ \ |/ /
 / ___/| | | (_| | |_| |  _  |  __/   < 
 \/    |_|  \__,_|\__,_|_| |_|\___|_|\_\
                                        
       Arch Linux 安装辅助脚本
EOF
    
    warn "重要警告：此脚本将格式化磁盘并安装新系统！"
    warn "请确保已备份所有重要数据！"
    echo ""
    
    # 执行安装步骤
    check_root
    check_network
    check_boot_mode
    show_disk_layout
    partition_disk
    mount_partitions
    select_mirrors
    install_base
    generate_fstab
    configure_system
    show_completion
}

# 执行主函数
main "$@"
