import 'dart:io';
import 'dart:ui' as ui;

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThermalPrinterService {
  static const _kindKey = 'saree_printer_kind';
  static const _addressKey = 'saree_printer_address';
  static const _nameKey = 'saree_printer_name';
  static const _portKey = 'saree_printer_port';
  static const _paperKey = 'saree_printer_paper';
  static const _autoKey = 'saree_printer_auto';

  static String _key(String base, String restaurantId) => '${base}_${restaurantId}';

  static Future<Map<String, dynamic>> settings(String restaurantId) async {
    final p = await SharedPreferences.getInstance();
    return {
      'kind': p.getString(_key(_kindKey, restaurantId)) ?? 'bluetooth',
      'address': p.getString(_key(_addressKey, restaurantId)) ?? '',
      'name': p.getString(_key(_nameKey, restaurantId)) ?? '',
      'port': p.getInt(_key(_portKey, restaurantId)) ?? 9100,
      'paper': p.getInt(_key(_paperKey, restaurantId)) ?? 80,
      'auto': p.getBool(_key(_autoKey, restaurantId)) ?? false,
    };
  }

  static Future<void> save({
    required String restaurantId,
    required String kind,
    required String address,
    required String name,
    required int port,
    required int paper,
    required bool auto,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key(_kindKey, restaurantId), kind);
    await p.setString(_key(_addressKey, restaurantId), address.trim());
    await p.setString(_key(_nameKey, restaurantId), name.trim());
    await p.setInt(_key(_portKey, restaurantId), port);
    await p.setInt(_key(_paperKey, restaurantId), paper);
    await p.setBool(_key(_autoKey, restaurantId), auto);
  }

  static Future<bool> autoPrint(String restaurantId) async =>
      (await settings(restaurantId))['auto'] == true;

  static Future<List<int>> _receiptBytes({
    required Map<String, dynamic> order,
    required List<Map<String, dynamic>> items,
    required String restaurantName,
    required int paper,
  }) async {
    final width = paper == 58 ? 384.0 : 576.0;
    final number = order['order_number']?.toString() ?? order['id']?.toString() ?? '';
    final lines = <String>[
      restaurantName,
      'فاتورة طلب رقم #$number',
      '--------------------------------',
      'العميل: ${order['customer_name'] ?? ''}',
      'الهاتف: ${order['customer_phone'] ?? ''}',
      'العنوان: ${order['delivery_address'] ?? ''}',
      '--------------------------------',
      'الصنف                 الكمية    السعر',
      ...items.map((item) {
        final name = item['item_name']?.toString() ?? 'صنف';
        final qty = (item['quantity'] as num?)?.toInt() ?? 0;
        final unit = (item['unit_price_yer'] as num?)?.toInt() ?? 0;
        final total = (item['line_total_yer'] as num?)?.toInt() ?? qty * unit;
        return '$name  × $qty  = $total ريال';
      }),
      '--------------------------------',
      'قيمة الأصناف: ${order['subtotal_yer'] ?? 0} ريال',
      'التوصيل: ${order['delivery_fee_yer'] ?? 0} ريال',
      'الإجمالي: ${order['total_yer'] ?? 0} ريال',
      if ((order['notes'] ?? '').toString().trim().isNotEmpty)
        'ملاحظات: ${order['notes']}',
      '--------------------------------',
      'شكراً لطلبكم من $restaurantName',
      '',
      '',
    ];
    final text = lines.join('\n');
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, 12000));
    canvas.drawColor(Colors.white, BlendMode.src);
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontFamily: 'SareeArabic',
          fontSize: 22,
          height: 1.45,
          color: Colors.black,
        ),
      ),
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.right,
    )..layout(maxWidth: width - 24);
    canvas.translate(12, 12);
    painter.paint(canvas, Offset.zero);
    final actualHeight = painter.height + 28;
    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), actualHeight.ceil());
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (png == null) throw Exception('تعذر تجهيز صورة الفاتورة');
    final decoded = img.decodeImage(png.buffer.asUint8List());
    if (decoded == null) throw Exception('تعذر تحويل الفاتورة للطباعة');

    final profile = await CapabilityProfile.load();
    final generator = Generator(
      paper == 58 ? PaperSize.mm58 : PaperSize.mm80,
      profile,
    );
    return <int>[
      ...generator.reset(),
      ...generator.imageRaster(decoded, align: PosAlign.center),
      ...generator.feed(3),
      ...generator.cut(),
    ];
  }

  static Future<void> printOrder({
    required String restaurantId,
    required Map<String, dynamic> order,
    required List<Map<String, dynamic>> items,
    required String restaurantName,
  }) async {
    final config = await settings(restaurantId);
    final address = (config['address'] as String).trim();
    if (address.isEmpty) throw Exception('اضبط الطابعة أولاً من إعدادات الطباعة');
    final bytes = await _receiptBytes(
      order: order,
      items: items,
      restaurantName: restaurantName,
      paper: config['paper'] as int,
    );
    if (config['kind'] == 'bluetooth') {
      final granted = await PrintBluetoothThermal.isPermissionBluetoothGranted;
      if (!granted) {
        throw Exception('اسمح للتطبيق بصلاحية أجهزة Bluetooth القريبة من إعدادات الهاتف');
      }
      final connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) {
        final ok = await PrintBluetoothThermal.connect(macPrinterAddress: address);
        if (!ok) throw Exception('تعذر الاتصال بالطابعة عبر Bluetooth');
      }
      final ok = await PrintBluetoothThermal.writeBytes(bytes);
      if (!ok) throw Exception('فشلت الطباعة عبر Bluetooth');
    } else {
      final port = config['port'] as int;
      final socket = await Socket.connect(address, port,
          timeout: const Duration(seconds: 6));
      try {
        socket.add(bytes);
        await socket.flush().timeout(const Duration(seconds: 10));
      } finally {
        await socket.close();
      }
    }
  }
}

class ThermalPrinterSettingsTab extends StatefulWidget {
  const ThermalPrinterSettingsTab({super.key, required this.restaurantName, required this.restaurantId});
  final String restaurantName;
  final String restaurantId;

  @override
  State<ThermalPrinterSettingsTab> createState() => _ThermalPrinterSettingsTabState();
}

class _ThermalPrinterSettingsTabState extends State<ThermalPrinterSettingsTab> {
  final _address = TextEditingController();
  final _port = TextEditingController(text: '9100');
  String _kind = 'bluetooth';
  String _name = '';
  int _paper = 80;
  bool _auto = false;
  bool _busy = false;
  List<dynamic> _devices = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await ThermalPrinterService.settings(widget.restaurantId);
    if (!mounted) return;
    setState(() {
      _kind = s['kind'] as String;
      _address.text = s['address'] as String;
      _name = s['name'] as String;
      _port.text = (s['port'] as int).toString();
      _paper = s['paper'] as int;
      _auto = s['auto'] as bool;
    });
  }

  Future<void> _scan() async {
    setState(() => _busy = true);
    try {
      final granted = await PrintBluetoothThermal.isPermissionBluetoothGranted;
      if (!granted) {
        throw Exception('فعّل صلاحية Bluetooth للأجهزة القريبة من إعدادات الهاتف ثم أعد المحاولة');
      }
      final enabled = await PrintBluetoothThermal.bluetoothEnabled;
      if (!enabled) throw Exception('شغّل Bluetooth في الهاتف أولاً');
      final devices = await PrintBluetoothThermal.pairedBluetooths;
      if (!mounted) return;
      setState(() => _devices = devices);
      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد طابعات مقترنة. اربط الطابعة من إعدادات Bluetooth في الهاتف أولاً.')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final port = int.tryParse(_port.text.trim()) ?? 9100;
    if (_address.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل عنوان الطابعة أو اخترها من القائمة')));
      return;
    }
    if (port < 1 || port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('رقم منفذ الشبكة غير صحيح')));
      return;
    }
    setState(() => _busy = true);
    try {
      await ThermalPrinterService.save(
        restaurantId: widget.restaurantId,
        kind: _kind,
        address: _address.text,
        name: _name,
        port: port,
        paper: _paper,
        auto: _auto,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ إعدادات الطابعة على هذا الجهاز')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    setState(() => _busy = true);
    try {
      await _save();
      await ThermalPrinterService.printOrder(
        restaurantId: widget.restaurantId,
        order: {
          'order_number': 'TEST',
          'customer_name': 'عميل تجريبي',
          'customer_phone': '000000000',
          'delivery_address': 'اختبار اتصال الطابعة',
          'subtotal_yer': 100,
          'delivery_fee_yer': 0,
          'total_yer': 100,
        },
        items: [
          {'item_name': 'فاتورة تجريبية', 'quantity': 1, 'unit_price_yer': 100, 'line_total_yer': 100},
        ],
        restaurantName: widget.restaurantName,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال الفاتورة التجريبية للطابعة')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الاختبار: ${e.toString().replaceFirst('Exception: ', '')}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _address.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text('ربط طابعة الفواتير الحرارية', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      const Text('اربط طابعة ESC/POS عبر Bluetooth أو شبكة المطعم. يجب أن يكون الهاتف والطابعة على الشبكة المحلية نفسها عند اختيار Wi-Fi.', style: TextStyle(height: 1.5)),
      const SizedBox(height: 16),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'bluetooth', label: Text('Bluetooth'), icon: Icon(Icons.bluetooth)),
          ButtonSegment(value: 'wifi', label: Text('Wi-Fi / IP'), icon: Icon(Icons.wifi)),
        ],
        selected: {_kind},
        onSelectionChanged: (v) => setState(() => _kind = v.first),
      ),
      const SizedBox(height: 12),
      if (_kind == 'bluetooth') ...[
        OutlinedButton.icon(
          onPressed: _busy ? null : _scan,
          icon: const Icon(Icons.search),
          label: Text(_busy ? 'جارٍ البحث...' : 'عرض الطابعات المقترنة'),
        ),
        ..._devices.map((device) => Card(
          child: ListTile(
            leading: const Icon(Icons.print),
            title: Text(device.name.toString()),
            subtitle: Text(device.macAdress.toString()),
            trailing: _address.text == device.macAdress.toString() ? const Icon(Icons.check_circle, color: Colors.green) : null,
            onTap: () => setState(() {
              _address.text = device.macAdress.toString();
              _name = device.name.toString();
            }),
          ),
        )),
        TextField(controller: _address, decoration: const InputDecoration(labelText: 'عنوان MAC للطابعة')),
      ] else ...[
        TextField(
          controller: _address,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'عنوان IP للطابعة', hintText: '192.168.1.100'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _port,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'منفذ الطباعة TCP', hintText: '9100'),
        ),
      ],
      const SizedBox(height: 12),
      DropdownButtonFormField<int>(
        value: _paper,
        decoration: const InputDecoration(labelText: 'عرض ورق الفاتورة'),
        items: const [
          DropdownMenuItem(value: 58, child: Text('58 mm')),
          DropdownMenuItem(value: 80, child: Text('80 mm')),
        ],
        onChanged: (v) => setState(() => _paper = v ?? 80),
      ),
      const SizedBox(height: 12),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _auto,
        onChanged: (v) => setState(() => _auto = v),
        title: const Text('طباعة الطلب الجديد تلقائياً'),
        subtitle: const Text('تعمل عند وصول الطلب والتطبيق مفتوح ومتصل بالإنترنت'),
      ),
      const SizedBox(height: 10),
      FilledButton.icon(
        onPressed: _busy ? null : _save,
        icon: const Icon(Icons.save_outlined),
        label: const Text('حفظ إعدادات الطابعة'),
      ),
      OutlinedButton.icon(
        onPressed: _busy ? null : _test,
        icon: const Icon(Icons.print_outlined),
        label: const Text('حفظ واختبار الطباعة'),
      ),
      const SizedBox(height: 10),
      const Text('ملاحظة: طابعات Bluetooth يجب إقرانها أولاً من إعدادات الهاتف. طباعة الشبكة تستخدم بروتوكول ESC/POS عبر TCP والمنفذ 9100 افتراضياً.', style: TextStyle(fontSize: 12, color: Color(0xFFDCE9DE), height: 1.5)),
    ],
  );
}
