// Scan screen: BLE device discovery with keyword filter support.
// 扫描页面：支持关键字筛选的蓝牙设备发现界面。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../utils/extra.dart';
import '../utils/snackbar.dart';
import '../widgets/scan_result_tile.dart';
import '../widgets/system_device_tile.dart';
import 'device_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _keywordController = TextEditingController();

  List<BluetoothDevice> _systemDevices = [];
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;

  // 当前已提交的关键字列表（用于实际扫描过滤）
  List<String> _activeKeywords = [];

  // 已输入但尚未提交的关键字标签列表（UI 展示）
  final List<String> _pendingKeywords = [];

  late StreamSubscription<List<ScanResult>> _scanResultsSubscription;
  late StreamSubscription<bool> _isScanningSubscription;

  @override
  void initState() {
    super.initState();

    _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() => _scanResults = results);
      }
    }, onError: (e) {
      Snackbar.show(ABC.b, prettyException("Scan Error:", e), success: false);
    });

    _isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      if (mounted) {
        setState(() => _isScanning = state);
      }
    });
  }

  @override
  void dispose() {
    _scanResultsSubscription.cancel();
    _isScanningSubscription.cancel();
    _keywordController.dispose();
    super.dispose();
  }

  /// 将输入框中的文字添加为关键字标签
  void _addKeyword() {
    final text = _keywordController.text.trim();
    if (text.isNotEmpty && !_pendingKeywords.contains(text)) {
      setState(() {
        _pendingKeywords.add(text);
        _keywordController.clear();
      });
    }
  }

  /// 从待提交列表中移除某个关键字
  void _removeKeyword(String keyword) {
    setState(() => _pendingKeywords.remove(keyword));
  }

  /// 清空所有关键字并重置过滤
  void _clearKeywords() {
    setState(() {
      _pendingKeywords.clear();
      _keywordController.clear();
    });
  }

  Future<void> _startScan() async {
    // Note: withKeywords is Android-only substring match;
    // 注意：withKeywords 在 Android 上以子字符串匹配，iOS 不支持。
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      withKeywords: _activeKeywords,
    );
  }

  Future onScanPressed() async {
    // 提交当前 pending 关键字作为本次扫描的过滤条件
    setState(() => _activeKeywords = List.from(_pendingKeywords));

    try {
      // `withServices` is required on iOS for privacy purposes, ignored on android.
      var withServices = [
        Guid("180f"), // battery
        Guid("180a"), // device info
        Guid("1800"), // generic access
        Guid("6e400001-b5a3-f393-e0a9-e50e24dcca9e"), // Nordic UART
      ];
      _systemDevices = await FlutterBluePlus.systemDevices(withServices);
    } catch (e, backtrace) {
      Snackbar.show(ABC.b, prettyException("System Devices Error:", e), success: false);
      print(e);
      print("backtrace: $backtrace");
    }
    try {
      await _startScan();
    } catch (e, backtrace) {
      Snackbar.show(ABC.b, prettyException("Start Scan Error:", e), success: false);
      print(e);
      print("backtrace: $backtrace");
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future onStopPressed() async {
    try {
      FlutterBluePlus.stopScan();
    } catch (e, backtrace) {
      Snackbar.show(ABC.b, prettyException("Stop Scan Error:", e), success: false);
      print(e);
      print("backtrace: $backtrace");
    }
  }

  void onConnectPressed(BluetoothDevice device) {
    device.connectAndUpdateStream().catchError((e) {
      Snackbar.show(ABC.c, prettyException("Connect Error:", e), success: false);
    });
    MaterialPageRoute route = MaterialPageRoute(
        builder: (context) => DeviceScreen(device: device), settings: RouteSettings(name: '/DeviceScreen'));
    Navigator.of(context).push(route);
  }

  Future onRefresh() {
    if (_isScanning == false) {
      _startScan();
    }
    if (mounted) {
      setState(() {});
    }
    return Future.delayed(Duration(milliseconds: 500));
  }

  /// 关键字筛选区域 Widget
  Widget _buildKeywordFilter(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.filter_list, size: 16),
              const SizedBox(width: 4),
              Text(
                'Keyword Filter',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (_activeKeywords.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Active: ${_activeKeywords.join(", ")}',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keywordController,
                  enabled: !_isScanning,
                  decoration: InputDecoration(
                    hintText: 'e.g. "MyDevice"',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onSubmitted: (_) => _addKeyword(),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                onPressed: _isScanning ? null : _addKeyword,
                icon: const Icon(Icons.add, size: 18),
                tooltip: 'Add keyword',
                style: IconButton.styleFrom(
                  minimumSize: const Size(36, 36),
                ),
              ),
              if (_pendingKeywords.isNotEmpty)
                IconButton(
                  onPressed: _isScanning ? null : _clearKeywords,
                  icon: const Icon(Icons.clear_all, size: 18),
                  tooltip: 'Clear all',
                ),
            ],
          ),
          if (_pendingKeywords.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _pendingKeywords.map((kw) {
                return Chip(
                  label: Text(kw, style: const TextStyle(fontSize: 12)),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: _isScanning ? null : () => _removeKeyword(kw),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: Snackbar.snackBarKeyB,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Find Devices'),
          actions: [
            if (_isScanning) CircularProgressIndicator(strokeWidth: 2.5),
            ElevatedButton(
              onPressed: _isScanning ? onStopPressed : onScanPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isScanning ? Theme.of(context).colorScheme.error : Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
              child: Text(_isScanning ? "STOP" : "SCAN"),
            ),
            const SizedBox(width: 15),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            controller: _scrollController,
            children: <Widget>[
              _buildKeywordFilter(context),
              ListView.builder(
                shrinkWrap: true,
                controller: _scrollController,
                itemCount: _systemDevices.length,
                itemBuilder: (context, index) {
                  final BluetoothDevice device = _systemDevices[index];
                  return SystemDeviceTile(
                    device: device,
                    onOpen: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => DeviceScreen(device: device),
                          settings: RouteSettings(name: '/DeviceScreen'),
                        ),
                      );
                    },
                    onConnect: () => onConnectPressed(device),
                  );
                },
              ),
              ListView.builder(
                shrinkWrap: true,
                controller: _scrollController,
                itemCount: _scanResults.length,
                itemBuilder: (context, index) {
                  final ScanResult result = _scanResults[index];
                  return ScanResultTile(
                    index: index,
                    result: result,
                    onTap: () => onConnectPressed(result.device),
                  );
                },
              ),
            ],
          ),
        ),
        // floatingActionButton: buildScanButton(context),
      ),
    );
  }
}
