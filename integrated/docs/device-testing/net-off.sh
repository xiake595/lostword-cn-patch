#!/system/bin/sh
# net-off.sh - 关闭模拟器所有网络（wifi / data / 飞行模式），防止游戏触发资源下载。
# 用法（屏幕上）：
#   adb.exe push net-off.sh /data/local/tmp/net-off.sh
#   adb.exe shell sh /data/local/tmp/net-off.sh
# 注意：模拟器上 svc data disable 可能抛异常（无电话服务），忽略即可；以 wifi/airplane/ping 为准。
svc wifi disable 2>/dev/null
svc data disable 2>/dev/null
settings put global airplane_mode_on 1
am broadcast -a android.intent.action.AIRPLANE_MODE >/dev/null 2>&1
sleep 1
echo "airplane_mode_on=$(settings get global airplane_mode_on)"
echo "wifi_state=$(dumpsys wifi 2>/dev/null | grep -m 1 'Wi-Fi is' | sed 's/^ *//')"
echo "default_network=$(dumpsys connectivity 2>/dev/null | grep -m 1 'Active default network' | sed 's/^ *//')"
echo -n "ping_8.8.8.8: "
ping -c 1 -W 2 8.8.8.8 2>&1 | tail -n 1
