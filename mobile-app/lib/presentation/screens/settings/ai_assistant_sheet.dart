import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// GeoTag AI — an interactive assistant preview. It accepts typed questions and
/// quick prompts and replies with helpful, on-device guidance. Wire [_reply] to
/// the AI backend when it ships; the chat UX stays exactly the same.
Future<void> showAiAssistantSheet(BuildContext context) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _AiAssistantSheet(),
  );
}

class _Msg {
  const _Msg(this.text, {required this.fromUser});
  final String text;
  final bool fromUser;
}

class _AiAssistantSheet extends StatefulWidget {
  const _AiAssistantSheet();

  @override
  State<_AiAssistantSheet> createState() => _AiAssistantSheetState();
}

class _AiAssistantSheetState extends State<_AiAssistantSheet> {
  static const Color _ink = Color(0xFF0F0F0F);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _bg = Color(0xFFFAFAFA);
  static const Color _hair = Color(0xFFE5E7EB);
  static const Color _purple = Color(0xFF7C3AED);

  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [];
  bool _thinking = false;

  static const _prompts = [
    'How much did I earn this week?',
    "What's my next ASAP job?",
    "What's the closest job to me?",
    "Summarize today's uploads",
    'Tips to get paid faster',
  ];

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(String raw) {
    final text = raw.trim();
    if (text.isEmpty || _thinking) return;
    HapticFeedback.selectionClick();
    setState(() {
      _messages.add(_Msg(text, fromUser: true));
      _thinking = true;
      _controller.clear();
    });
    _scrollToEnd();
    // Simulate a short "thinking" beat, then answer locally.
    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() {
        _thinking = false;
        _messages.add(_Msg(_reply(text), fromUser: false));
      });
      _scrollToEnd();
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Lightweight on-device responder. Swap for a real model call when ready.
  String _reply(String q) {
    final l = q.toLowerCase();
    if (l.contains('closest') ||
        l.contains('nearest') ||
        l.contains('near me')) {
      return 'Your jobs are sorted nearest-first on the Home feed and in the '
          'Log — the top card is the closest one to where you are right now. '
          'Open the Map and tap the location button to recenter, or pick a '
          'service filter to see the closest job of just that type.';
    }
    if (l.contains('earn') || l.contains('paid') || l.contains('money') ||
        l.contains('payout')) {
      return 'Open the Earnings tab to see today, this week, and bi-weekly '
          'payouts. To get paid faster: upload right after each job, attach a '
          'clear geotagged photo, and clear your ASAP queue first — those pay '
          'at the highest rate.';
    }
    if (l.contains('asap') || l.contains('next') || l.contains('job') ||
        l.contains('schedule')) {
      return 'Your next jobs live in the Schedule, grouped as ASAP, Next Day, '
          'Standard, and Special. ASAP jobs are time-sensitive — tackle those '
          'first. Want me to prioritize your route around the closest ASAP pin?';
    }
    if (l.contains('upload') || l.contains('photo') || l.contains('today')) {
      return "Today's uploads appear in the Log, newest first. With Auto-Tag "
          'on, each photo is captioned and categorized by location '
          'automatically — just review and confirm before submitting.';
    }
    if (l.contains('route') || l.contains('map') || l.contains('navigate')) {
      return 'Smart Suggestions can order your stops to cut driving time. '
          'Open the Map, tap a pin, and choose “Optimize route” to sequence '
          'your remaining jobs from where you are now.';
    }
    return 'I can help with earnings, your schedule, uploads, and routing. '
        'Try one of the prompts above, or ask about a specific job or payout.';
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final height = MediaQuery.of(context).size.height;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SizedBox(
        height: height * 0.8,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: _hair, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            _header(),
            const Divider(height: 1, color: _hair),
            Expanded(
              child: _messages.isEmpty ? _empty() : _list(),
            ),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 21),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('GeoTag AI',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _ink)),
                Text('Your intelligent field copilot',
                    style: TextStyle(fontSize: 12.5, color: _muted)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded, color: _muted),
          ),
        ]),
      );

  Widget _empty() => ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        children: [
          const Text('TRY ASKING',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _muted,
                  letterSpacing: 0.8)),
          const SizedBox(height: 12),
          for (final p in _prompts) _promptChip(p),
        ],
      );

  Widget _promptChip(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () => _send(text),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: _hair),
            ),
            child: Row(children: [
              const Icon(Icons.auto_awesome_rounded, size: 16, color: _purple),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(text,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _ink))),
              const Icon(Icons.north_west_rounded, size: 15, color: _muted),
            ]),
          ),
        ),
      );

  Widget _list() => ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        itemCount: _messages.length + (_thinking ? 1 : 0),
        itemBuilder: (context, i) {
          if (_thinking && i == _messages.length) {
            return _bubble(
              const Text('Thinking…',
                  style: TextStyle(
                      fontSize: 14,
                      color: _muted,
                      fontStyle: FontStyle.italic)),
              fromUser: false,
            );
          }
          final m = _messages[i];
          return _bubble(
            Text(m.text,
                style: TextStyle(
                    fontSize: 14.5,
                    height: 1.35,
                    color: m.fromUser ? Colors.white : _ink)),
            fromUser: m.fromUser,
          );
        },
      );

  Widget _bubble(Widget child, {required bool fromUser}) => Align(
        alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: fromUser ? _purple : _bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(fromUser ? 16 : 4),
              bottomRight: Radius.circular(fromUser ? 4 : 16),
            ),
            border: fromUser ? null : Border.all(color: _hair),
          ),
          child: child,
        ),
      );

  Widget _composer() => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 2, 6, 2),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: _hair),
                ),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: _send,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(fontSize: 14.5, color: _ink),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'Message GeoTag AI…',
                        hintStyle: TextStyle(fontSize: 14.5, color: _muted),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _send(_controller.text),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)]),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(Icons.arrow_upward_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 6),
              const Text('AI can make mistakes. Verify important details.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
            ],
          ),
        ),
      );
}
