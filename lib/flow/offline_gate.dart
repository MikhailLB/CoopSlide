import 'package:flutter/material.dart';

class OfflineGate extends StatefulWidget {
  final WidgetBuilder retryBuilder;

  const OfflineGate({super.key, required this.retryBuilder});

  @override
  State<OfflineGate> createState() => _OfflineGateState();
}

class _OfflineGateState extends State<OfflineGate> {
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: widget.retryBuilder),
    );
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final screenWidth = MediaQuery.of(context).size.width;
    final art = landscape
        ? 'assets/nowifi/nowifi_hor.webp'
        : 'assets/nowifi/nowifi_vert.webp';
    // In landscape the background tablet only occupies the central portion of
    // the screen, so constrain the Retry button to a similar width instead of
    // stretching it across the whole width.
    final buttonWidth = landscape
        ? screenWidth * 0.32
        : double.infinity;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(art, fit: BoxFit.cover),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  28,
                  0,
                  28,
                  landscape ? 24 : 48,
                ),
                child: SizedBox(
                  width: buttonWidth,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _retrying ? null : _retry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFA630),
                      disabledBackgroundColor:
                          const Color(0xFFFFA630).withValues(alpha: 0.45),
                      foregroundColor: const Color(0xFF4A2C10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: const BorderSide(color: Colors.white, width: 2),
                      ),
                      elevation: 6,
                    ),
                    child: _retrying
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Color(0xFF4A2C10),
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Connecting...',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          )
                        : const Text(
                            'Retry',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              letterSpacing: 0.5,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
