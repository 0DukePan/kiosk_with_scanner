import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'dart:math';

class QRCodePage extends StatefulWidget {
  @override
  _QRCodePageState createState() => _QRCodePageState();
}

class _QRCodePageState extends State<QRCodePage> with SingleTickerProviderStateMixin {
  String? _deviceId;
  bool _loading = true;
  String? _error;
  late AnimationController _animationController;
  late Animation<double> _bubbleAnimation;
  final Random _random = Random();

  // List of bubble configurations for more dynamic animation
  final List<BubbleConfig> _bubbles = [];

  @override
  void initState() {
    super.initState();
    _fetchDeviceId();
    
    // Generate random bubbles for background
    _generateBubbles();
    
    // Initialize animation controller
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 30),
    )..repeat();
    
    _bubbleAnimation = Tween<double>(begin: 0, end: 1).animate(_animationController);
  }
  
  void _generateBubbles() {
    _bubbles.clear();
    for (int i = 0; i < 15; i++) {
      _bubbles.add(
        BubbleConfig(
          size: _random.nextDouble() * 100 + 60,
          posX: _random.nextDouble(),
          posY: _random.nextDouble(),
          opacity: _random.nextDouble() * 0.25 + 0.15,
          speedX: (_random.nextDouble() - 0.5) * 0.08,
          speedY: (_random.nextDouble() - 0.5) * 0.08,
          color: [
            Color(0xffFBAF03),
            Colors.purple,
            Colors.blue,
            Colors.pinkAccent,
          ][_random.nextInt(4)],
        ),
      );
    }
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _fetchDeviceId() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      String? storedId = prefs.getString('tableDeviceId');
      if (storedId != null && storedId.isNotEmpty) {
        setState(() {
          _deviceId = storedId;
          _loading = false;
        });
        return;
      }
      final deviceInfoPlugin = DeviceInfoPlugin();
      String uniqueId = 'unknown_§0${DateTime.now().millisecondsSinceEpoch}_§00';

      if (kIsWeb) {
        String? webId = prefs.getString('webDeviceId');
        if (webId == null) {
          webId = 'web_§0${DateTime.now().millisecondsSinceEpoch}_§00';
          await prefs.setString('webDeviceId', webId);
        }
        uniqueId = webId;
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        uniqueId = "android_§0${androidInfo.id}";
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        uniqueId = "ios_§${iosInfo.identifierForVendor ?? '§00'}";
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfoPlugin.linuxInfo;
        uniqueId = "linux_§${linuxInfo.machineId ?? '§00'}";
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfoPlugin.macOsInfo;
        uniqueId = "macos_§${macInfo.systemGUID ?? '§00'}";
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfoPlugin.windowsInfo;
        uniqueId = "windows_§${windowsInfo.deviceId.isNotEmpty ? windowsInfo.deviceId : windowsInfo.computerName}";
      }

      await prefs.setString('tableDeviceId', uniqueId);
      setState(() {
        _deviceId = uniqueId;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to get device ID: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Device QR Code', 
          style: TextStyle(
            fontFamily: 'ProductSans',
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 22,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          // Animated Background with Bubbles
          _buildAnimatedBackground(),
          
          // Content
          SafeArea(
            child: _loading
                ? _buildLoadingWidget()
                : _error != null
                    ? _buildErrorWidget()
                    : _buildQRContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBackground() {
    return AnimatedBuilder(
      animation: _bubbleAnimation,
      builder: (context, child) {
        final size = MediaQuery.of(context).size;
        final t = _animationController.value;
        return Stack(
          children: [
            // Base gradient background
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF111111),
                    Color(0xFF0A0A0A),
                  ],
                ),
              ),
            ),
            // Dynamic bubbles
            ..._bubbles.map((bubble) {
              // Animate position in a loop, wrap around edges
              double x = (bubble.posX + bubble.speedX * t) % 1.2;
              double y = (bubble.posY + bubble.speedY * t) % 1.2;
              // If out of bounds, wrap
              if (x < 0) x += 1.2;
              if (y < 0) y += 1.2;
              return Positioned(
                left: size.width * x - bubble.size / 2,
                top: size.height * y - bubble.size / 2,
                child: Opacity(
                  opacity: bubble.opacity,
                  child: Container(
                    width: bubble.size,
                    height: bubble.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          bubble.color.withOpacity(bubble.opacity * 1.5),
                          bubble.color.withOpacity(0),
                        ],
                        stops: [0.2, 1.0],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
            // Overlay to soften the bubbles
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.2),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLoadingWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: -5,
                ),
              ],
            ),
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
              strokeWidth: 3,
            ),
          ),
          SizedBox(height: 30),
          Text(
            'Generating your unique ID...',
            style: TextStyle(
              fontFamily: 'ProductSans',
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          )
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 30),
        padding: EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 15,
              spreadRadius: -5,
            ),
          ],
          border: Border.all(
            color: Colors.white.withOpacity(0.08),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 70,
              color: Colors.red.shade300,
            ),
            SizedBox(height: 24),
            Text(
              'Error',
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'ProductSans',
                color: Colors.white.withOpacity(0.7),
                fontSize: 16,
              ),
            ),
            SizedBox(height: 28),
            ElevatedButton(
              onPressed: _fetchDeviceId,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                elevation: 8,
                shadowColor: Theme.of(context).primaryColor.withOpacity(0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: Text(
                'Try Again',
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQRContent() {
    final primaryColor = Theme.of(context).primaryColor;
    
    return SingleChildScrollView(
      physics: BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(height: 20),
            
            // Animated Title
            _buildAnimatedWidget(
              duration: Duration(milliseconds: 800),
              child: Text(
                'Your Device ID',
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            
            SizedBox(height: 12),
            
            // Subtitle
            _buildAnimatedWidget(
              duration: Duration(milliseconds: 800),
              child: Text(
                'Scan to connect this device',
                style: TextStyle(
                  fontFamily: 'ProductSans',
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 17,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            
            SizedBox(height: 50),
            
            // QR Code Container
            _buildAnimatedWidget(
              duration: Duration(milliseconds: 1200),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withOpacity(0.25),
                      blurRadius: 30,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                padding: EdgeInsets.all(4),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: primaryColor,
                      width: 4,
                    ),
                  ),
                  padding: EdgeInsets.all(18),
                  child: QrImageView(
                    data: _deviceId!,
                    version: QrVersions.auto,
                    size: 200.0,
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    eyeStyle: QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: primaryColor,
                    ),
                    dataModuleStyle: QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                    embeddedImage: AssetImage('assets/images/logo_small.png'),
                    embeddedImageStyle: QrEmbeddedImageStyle(
                      size: Size(40, 40),
                    ),
                  ),
                ),
              ),
            ),
            
            SizedBox(height: 50),
            
            // Device ID Display
            _buildAnimatedWidget(
              duration: Duration(milliseconds: 800),
              child: Container(
                margin: EdgeInsets.symmetric(horizontal: 5),
                padding: EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 15,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.smartphone_rounded,
                          color: primaryColor,
                          size: 22,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Device ID',
                          style: TextStyle(
                            fontFamily: 'ProductSans',
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    SelectableText(
                      _deviceId!,
                      style: TextStyle(
                        color: primaryColor,
                        fontSize: 15,
                        fontFamily: 'monospace',
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: 40),
            
            // Copy Button
            _buildAnimatedWidget(
              duration: Duration(milliseconds: 800),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: primaryColor.withOpacity(0.4),
                      blurRadius: 20,
                      offset: Offset(0, 8),
                      spreadRadius: -5,
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _deviceId!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          "Device ID copied to clipboard!",
                          style: TextStyle(
                            fontFamily: 'ProductSans',
                          ),
                        ),
                        backgroundColor: primaryColor,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        margin: EdgeInsets.all(10),
                      ),
                    );
                  },
                  icon: Icon(Icons.copy_rounded),
                  label: Text(
                    'Copy ID',
                    style: TextStyle(
                      fontFamily: 'ProductSans',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ),
            
            SizedBox(height: 30),
            
            // Help Text
            _buildAnimatedWidget(
              duration: Duration(milliseconds: 800),
              child: Container(
                margin: EdgeInsets.symmetric(horizontal: 5),
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: Colors.white.withOpacity(0.8),
                          size: 22,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'How to use',
                          style: TextStyle(
                            fontFamily: 'ProductSans',
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Scan this QR code to get the unique device ID for registration or pairing with other applications.',
                      style: TextStyle(
                        fontFamily: 'ProductSans',
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAnimatedWidget({
    required Duration duration,
    required Widget child,
  }) {
    return TweenAnimationBuilder(
      duration: duration,
      curve: Curves.easeOut,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, double value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

// Class to hold bubble configuration for animations
class BubbleConfig {
  final double size;
  final double posX;
  final double posY;
  final double opacity;
  final double speedX;
  final double speedY;
  final Color color;
  
  BubbleConfig({
    required this.size,
    required this.posX,
    required this.posY,
    required this.opacity,
    required this.speedX,
    required this.speedY,
    required this.color,
  });
}


