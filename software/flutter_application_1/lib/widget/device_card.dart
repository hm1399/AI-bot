import 'package:flutter/material.dart';
import '../models/device_status.dart';

class DeviceCard extends StatelessWidget {
  final DeviceStatus status;

  const DeviceCard({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('设备状态', style: Theme.of(context).textTheme.titleLarge),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: status.isOnline ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status.isOnline ? '在线' : '离线',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem(
                    Icons.battery_full,
                    '电量',
                    '${status.batteryLevel}%',
                  ),
                ),
                Expanded(
                  child: _buildInfoItem(
                    Icons.wifi,
                    '信号',
                    '${status.wifiStrength}%',
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem(
                    Icons.mic,
                    '模式',
                    _modeToString(status.mode),
                  ),
                ),
                Expanded(
                  child: _buildInfoItem(
                    status.isMuted ? Icons.mic_off : Icons.mic,
                    '静音',
                    status.isMuted ? '是' : '否',
                  ),
                ),
                Expanded(
                  child: _buildInfoItem(
                    status.ledOn ? Icons.lightbulb : Icons.lightbulb_outline,
                    'LED',
                    status.ledOn ? '开' : '关',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon),
        SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12)),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  String _modeToString(DeviceMode mode) {
    switch (mode) {
      case DeviceMode.standby:
        return '待机';
      case DeviceMode.recording:
        return '录音中';
      case DeviceMode.playing:
        return '播放中';
    }
  }
}