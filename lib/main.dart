import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NUMB',
      theme: ThemeData(primarySwatch: Colors.green, scaffoldBackgroundColor: Colors.white),
      home: MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class Song {
  final String title, artist, hash;
  final String? cover;
  const Song({required this.title, required this.artist, required this.hash, this.cover});
  factory Song.fromJson(Map<String, dynamic> j) => Song(
    title: j['SongName'] ?? '',
    artist: j['SingerName'] ?? '',
    hash: j['FileHash'] ?? '',
    cover: 'https://imge.kugou.com/stdmusic/200/20210526/20210526143325_4f3a2c8e9b1d.jpg',
  );
}

class Api {
  static const headers = {'User-Agent': 'Mozilla/5.0'};
  static Future<List<Song>> search(String kw) async {
    try {
      final r = await http.get(Uri.parse('https://songsearch.kugou.com/song_search_v2?keyword=$kw&page=1&pagesize=30'), headers: headers);
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        return (d['data']['lists'] as List).map((e) => Song.fromJson(e)).toList();
      }
    } catch (e) { debugPrint('err: $e'); }
    return [];
  }
  static Future<String?> getUrl(String hash) async {
    try {
      final r = await http.get(Uri.parse('https://m.kugou.com/app/i/getSongInfo.php?cmd=playInfo&hash=$hash'), headers: headers);
      if (r.statusCode == 200) { final d = jsonDecode(r.body); return d['url']; }
    } catch (e) {}
    return null;
  }
}

class Player extends ChangeNotifier {
  final AudioPlayer _ap = AudioPlayer();
  List<Song> _list = [];
  int _idx = 0;
  bool _playing = false;
  Duration _pos = Duration.zero, _dur = Duration.zero;

  Song? get current => _idx < _list.length ? _list[_idx] : null;
  bool get playing => _playing;
  Duration get pos => _pos;
  Duration get dur => _dur;

  Player() {
    _ap.onPositionChanged.listen((p) { _pos = p; notifyListeners(); });
    _ap.onDurationChanged.listen((d) { _dur = d; notifyListeners(); });
    _ap.onPlayerComplete.listen((_) => next());
  }

  void play(List<Song> list, int i) async {
    _list = list; _idx = i;
    final url = await Api.getUrl(list[i].hash);
    if (url != null) { await _ap.play(UrlSource(url)); _playing = true; notifyListeners(); }
  }
  void toggle() async { _playing ? await _ap.pause() : await _ap.resume(); _playing = !_playing; notifyListeners(); }
  void next() => play(_list, (_idx + 1) % _list.length);
  void prev() => play(_list, (_idx - 1 + _list.length) % _list.length);
  void seek(Duration d) async { await _ap.seek(d); _pos = d; notifyListeners(); }
}

class MainScreen extends StatefulWidget {
  @override
  State<MainScreen> createState() => _MainScreenState();
}
class _MainScreenState extends State<MainScreen> {
  int _tab = 0;
  final Player _pc = Player();
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pc,
      builder: (_, __) => Scaffold(
        body: Column(children: [
          Expanded(child: IndexedStack(index: _tab, children: [HomePage(pc: _pc), SearchPage(pc: _pc), ProfilePage()])),
          if (_pc.current != null) _mini(),
        ]),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _tab, onTap: (i) => setState(() => _tab = i),
          items: [BottomNavigationBarItem(icon: Icon(Icons.home), label: '首页'),
                  BottomNavigationBarItem(icon: Icon(Icons.search), label: '搜索'),
                  BottomNavigationBarItem(icon: Icon(Icons.person), label: '我的')],
        ),
      ),
    );
  }
  Widget _mini() {
    final s = _pc.current!;
    return Container(margin: EdgeInsets.all(8), padding: EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
      child: Row(children: [
        Icon(Icons.music_note, color: Colors.green), SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(s.title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1),
          Text(s.artist, style: TextStyle(color: Colors.grey, fontSize: 11), maxLines: 1),
        ])),
        IconButton(icon: Icon(_pc.playing ? Icons.pause : Icons.play_arrow, color: Colors.green), onPressed: _pc.toggle),
        IconButton(icon: Icon(Icons.skip_next, color: Colors.green), onPressed: _pc.next),
      ]));
  }
}

class HomePage extends StatefulWidget {
  final Player pc;
  HomePage({required this.pc});
  @override
  State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  List<Song> _songs = [];
  bool _loading = true;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final s = await Api.search('热歌榜 2026');
    setState(() { _songs = s; _loading = false; });
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('NUMB音乐'), backgroundColor: Colors.green),
      body: _loading ? Center(child: CircularProgressIndicator()) : ListView.builder(
        itemCount: _songs.length,
        itemBuilder: (_, i) => ListTile(
          leading: CircleAvatar(child: Text('${i+1}')),
          title: Text(_songs[i].title),
          subtitle: Text(_songs[i].artist),
          onTap: () => widget.pc.play(_songs, i),
        ),
      ),
    );
  }
}

class SearchPage extends StatefulWidget {
  final Player pc;
  SearchPage({required this.pc});
  @override
  State<SearchPage> createState() => _SearchPageState();
}
class _SearchPageState extends State<SearchPage> {
  List<Song> _songs = [];
  bool _loading = false;
  final _ctrl = TextEditingController();
  Future<void> _search() async {
    setState(() => _loading = true);
    final s = await Api.search(_ctrl.text);
    setState(() { _songs = s; _loading = false; });
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: TextField(controller: _ctrl, decoration: InputDecoration(hintText: '搜索歌曲...'), onSubmitted: (_) => _search())),
      body: _loading ? Center(child: CircularProgressIndicator()) : ListView.builder(
        itemCount: _songs.length,
        itemBuilder: (_, i) => ListTile(
          leading: Icon(Icons.music_note),
          title: Text(_songs[i].title),
          subtitle: Text(_songs[i].artist),
          onTap: () => widget.pc.play(_songs, i),
        ),
      ),
    );
  }
}

class ProfilePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text('我的')), body: Center(child: Text('NUMB v1.0')));
}
