import 'package:flutter/material.dart';
import '../models/device_status.dart';

class DeviceCard extends StatelessWidget {
  final DeviceStatus? status;
  final bool isLoading;
  final VoidCallback? onRefresh;
  final VoidCallback? onMuteToggle;
  final VoidCallback? onLedToggle;
  final VoidCallback? onRestart;
  
  const DeviceCard({
    Key? key,
    this.status,
    this.isLoading = false,
    this.onRefresh,
    this.onMuteToggle,
    this.onLedToggle,
    this.onRestart,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      margin: const EdgeInsets.all(16.0),
      elevation: 4.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '设备状态',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: isLoading 
                      ? const SizedBox(
                          width: 20.0,
                          height: 20.0,
                          child: CircularProgressIndicator(strokeWidth: 2.0),
                        )
                      : const Icon(Icons.refresh),
                  onPressed: onRefresh,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
            const SizedBox(height: 16.0),
            
            if (status == null)
              _buildNoStatus(context)
            else
              _buildStatusContent(context),
          ],
        ),
      ),
    );
  }
  
  Widget _buildNoStatus(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Icon(
            Icons.device_unknown,
            size: 64.0,
            color: Theme.of(context).disabledColor,
          ),
          const SizedBox(height: 16.0),
          Text(
            '无法获取设备状态',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8.0),
          Text(
            '请检查设备连接',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).disabledColor,
                ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatusContent(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 连接状态
        _buildStatusRow(
          context,
          '连接状态',
          status!.isOnline ? '在线' : '离线',
          status!.isOnline 
              ? theme.colorScheme.primary 
              : theme.colorScheme.error,
        ),
        
        // 电池电量
        _buildStatusRow(
          context,
          '电池电量',
          '${status!.batteryLevel}%',
          _getBatteryColor(status!.batteryLevel),
        ),
        
        // WiFi信号
        _buildStatusRow(
          context,
          'WiFi信号',
          '${status!.wifiSignalStrength}%',
          theme.colorScheme.primary,
        ),
        
        // 设备状态
        _buildStatusRow(
          context,
          '当前状态',
          _getDeviceStateText(status!.state),
          theme.colorScheme.secondary,
        ),
        
        // 最后更新时间
        Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text(
            '最后更新: ${_formatLastUpdated(status!.lastUpdated)}',
            style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.disabledColor,
                ),
          ),
        ),
        
        // 快捷操作按钮
        const SizedBox(height: 24.0),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildActionButton(
              context,
              Icons.volume_up,
              '静音',
              onMuteToggle,
            ),
            _buildActionButton(
              context,
              Icons.lightbulb,
              'LED',
              onLedToggle,
            ),
            _buildActionButton(
              context,
              Icons.restart_alt,
              '重启',
              onRestart,
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildStatusRow(BuildContext context, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildActionButton(BuildContext context, IconData icon, String label, VoidCallback? onPressed) {
    return Column(
      children: [
        CircleAvatar(
          radius: 24.0,
          backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
          child: IconButton(
            icon: Icon(icon),
            onPressed: onPressed,
            color: Theme.of(context).colorScheme.primary,
            iconSize: 24.0,
            padding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(height: 4.0),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
  
  Color _getBatteryColor(int level) {
    if (level > 60) {
      return Colors.green;
    } else if (level > 30) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }
  
  String _getDeviceStateText(DeviceState state) {
    switch (state) {
      case DeviceState.standby:
        return '待机';
      case DeviceState.recording:
        return '录音中';
      case DeviceState.playing:
        return '播放中';
      default:
        return '未知';
    }
  }
  
  String _formatLastUpdated(DateTime lastUpdated) {
    final now = DateTime.now();
    final difference = now.difference(lastUpdated);
    
    if (difference.inMinutes < 1) {
      return '刚刚';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}分钟前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}小时前';
    } else {
      return '${difference.inDays}天前';
    }
  }
}