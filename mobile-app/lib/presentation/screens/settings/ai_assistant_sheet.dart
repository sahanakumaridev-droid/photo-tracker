import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/copilot.dart';
import '../../../core/ai/spoken_parser.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/location_service.dart';
import '../../../data/models/company.dart';
import '../../providers/photo_provider.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/ai/voice_mic_button.dart';

/// GeoTag AI — talk or type. Answers with live jobs/earnings and can create
/// a profile from one spoken sentence.
Future<void> showAiAssistantSheet(BuildContext context) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFFFFFFFF),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const AiAssistantSheet(),
  );
}

class _Msg {
  const _Msg(this.text, {required this.fromUser, this.draft});
  final String text;
  final bool fromUser;
  final SpokenDraft? draft;
}

class AiAssistantSheet extends ConsumerStatefulWidget {
  const AiAssistantSheet({super.key});

  @override
  ConsumerState<AiAssistantSheet> createState() => _AiAssistantSheetState();
}

class _AiAssistantSheetState extends ConsumerState<AiAssistantSheet> {
  static const Color _ink = Color(0xFF1A2130);
  static const Color _muted = Color(0xFF5C6778);
  static const Color _bg = Color(0xFFF2F4F7);
  static const Color _hair = Color(0xFFE3E7EE);
  static const Color _purple = Color(0xFF4A90E2);

  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [];
  bool _thinking = false;
  bool _creating = false;
  Map<String, dynamic>? _earnings;
  Position? _position;

  static const _prompts = [
    'How much is available?',
    'What’s the closest job?',
    'Create a profile by voice',
    'How do I add an attempt?',
    'Search by saying a ZIP',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetch());
  }

  Future<void> _prefetch() async {
    try {
      final api = ref.read(apiServiceProvider);
      final earnings = await api.getEarnings(period: 'week');
      if (mounted) setState(() => _earnings = earnings);
    } catch (_) {}
    try {
      final pos = await LocationService.getCurrentLocation();
      if (mounted) setState(() => _position = pos);
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  CopilotContext get _ctx => CopilotContext(
        profiles: ref.read(profilesProvider).valueOrNull ?? const [],
        photos: ref.read(photosProvider).valueOrNull ?? const [],
        earnings: _earnings,
        position: _position,
      );

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
    Future.delayed(const Duration(milliseconds: 420), () async {
      if (!mounted) return;
      final reply = answerCopilot(text, _ctx);
      setState(() {
        _thinking = false;
        _messages.add(_Msg(reply.text,
            fromUser: false, draft: reply.createDraft));
      });
      _scrollToEnd();
      if (reply.createDraft == null &&
          reply.route != null &&
          _shouldAutoOpen(text)) {
        await Future<void>.delayed(const Duration(milliseconds: 550));
        if (!mounted) return;
        Navigator.of(context).maybePop();
        if (context.mounted) context.go(reply.route!);
      }
    });
  }

  bool _shouldAutoOpen(String text) {
    final l = text.toLowerCase();
    return l.contains('open') ||
        l.contains('show') ||
        l.contains('go to') ||
        l.contains('take me') ||
        l.contains('how much') ||
        l.contains('closest') ||
        l.contains('nearest');
  }

  Future<void> _createFromDraft(SpokenDraft draft) async {
    if (_creating || draft.name == null) return;
    setState(() => _creating = true);
    try {
      await ref.read(createProfileProvider((
        name: draft.name!.trim(),
        serviceType: draft.priority ??
            defaultPriorityForCompany(draft.companyId),
        company: draft.companyId ?? kDefaultCompanyId,
        payRate: draft.payRate,
        deliveryStyle: null,
        status: 'awaiting_attempt',
        address: draft.address,
        city: draft.city,
        state: draft.state,
        postalCode: draft.postalCode,
        latitude: null,
        longitude: null,
      )).future);
      ref.invalidate(profilesProvider);
      if (!mounted) return;
      setState(() {
        _creating = false;
        _messages.add(const _Msg(
          'Profile saved. It’s on Home as a pin once you set a location — '
          'or open it from Profiles.',
          fromUser: false,
        ));
      });
      _scrollToEnd();
    } catch (_) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create that profile')),
      );
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 140,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final height = MediaQuery.of(context).size.height;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SizedBox(
        height: height * 0.82,
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
                  colors: [Color(0xFF4A90E2), Color(0xFF1E88E5)]),
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
                Text('Talk — don’t type',
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
          const Text('TRY SAYING',
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
          onTap: () => _send(
            text.toLowerCase().contains('voice')
                ? 'Create a new profile'
                : text,
          ),
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.text.replaceAll('**', ''),
                    style: TextStyle(
                        fontSize: 14.5,
                        height: 1.35,
                        color: m.fromUser ? Colors.white : _ink)),
                if (m.draft != null) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: _creating ? null : () => _createFromDraft(m.draft!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _purple,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _creating ? 'Creating…' : 'Create profile',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
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
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: _hair),
                ),
                child: Row(children: [
                  VoiceMicButton(
                    controller: _controller,
                    mode: VoiceFillMode.replace,
                    tooltip: 'Talk to GeoTag AI',
                  ),
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
                        hintText: 'Talk or type…',
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
                            colors: [Color(0xFF4A90E2), Color(0xFF1E88E5)]),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(Icons.arrow_upward_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 6),
              const Text(
                  'Tap the mic and speak. AI can make mistakes — verify payouts.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
            ],
          ),
        ),
      );
}
