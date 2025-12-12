import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

// 【⚠️注意】部署完后端后，回来把这个地址改成你的 Render/Railway 网址
// 格式如: https://baobo-server.onrender.com
const String baseUrl = 'http://REPLACE_ME_WITH_YOUR_SERVER_URL'; 

void main() {
  runApp(const MaterialApp(home: MainPage()));
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});
  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;
  final List<Widget> _pages = [
    const HomePage(),
    const FeedPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.security), label: '生活'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: '广场'),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('胞波通'), backgroundColor: Colors.teal),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Card(child: ListTile(leading: Icon(Icons.warning, color: Colors.red), title: Text("公告：仰光某区今晚宵禁"))),
          SizedBox(height: 10),
          Text("💰 参考汇率", style: TextStyle(fontWeight: FontWeight.bold)),
          Card(child: ListTile(title: Text("人民币 (CNY)"), trailing: Text("485 / 495"))),
        ],
      ),
    );
  }
}

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});
  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  List posts = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchPosts();
  }

  Future<void> fetchPosts() async {
    if (baseUrl.contains("REPLACE_ME")) {
      setState(() => isLoading = false);
      return; // 防止未配置地址时报错
    }
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/posts'));
      if (res.statusCode == 200) {
        setState(() {
          posts = json.decode(res.body);
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('华人广场'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UploadPage())),
          )
        ],
      ),
      body: isLoading ? const Center(child: CircularProgressIndicator()) : 
            posts.isEmpty ? const Center(child: Text("暂无帖子或未连接服务器")) :
            ListView.builder(
              itemCount: posts.length,
              itemBuilder: (ctx, i) => PostCard(post: posts[i]),
            ),
    );
  }
}

class PostCard extends StatelessWidget {
  final Map post;
  const PostCard({super.key, required this.post});
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Column(
        children: [
          ListTile(title: Text(post['username'] ?? '匿名'), subtitle: Text(post['content'] ?? '')),
          if (post['media_url'] != null && post['file_type'] == 'video')
            SizedBox(height: 200, child: VideoWidget(url: post['media_url'])),
          if (post['media_url'] != null && post['file_type'] == 'image')
             Image.network(post['media_url']),
        ],
      ),
    );
  }
}

class VideoWidget extends StatefulWidget {
  final String url;
  const VideoWidget({super.key, required this.url});
  @override
  State<VideoWidget> createState() => _VideoWidgetState();
}
class _VideoWidgetState extends State<VideoWidget> {
  late VideoPlayerController _vc;
  ChewieController? _cc;
  @override
  void initState() {
    super.initState();
    _vc = VideoPlayerController.networkUrl(Uri.parse(widget.url))..initialize().then((_) {
      setState(() => _cc = ChewieController(videoPlayerController: _vc, autoPlay: false, looping: false));
    });
  }
  @override
  void dispose() { _vc.dispose(); _cc?.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return _cc != null ? Chewie(controller: _cc!) : const Center(child: CircularProgressIndicator());
  }
}

class UploadPage extends StatefulWidget {
  const UploadPage({super.key});
  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final _txt = TextEditingController();
  XFile? _file;
  bool _ing = false;
  final _picker = ImagePicker();

  Future<void> _up() async {
    if (baseUrl.contains("REPLACE_ME")) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先配置服务器地址')));
        return;
    }
    setState(() => _ing = true);
    var req = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/upload'));
    req.fields['username'] = 'User';
    req.fields['text'] = _txt.text;
    if (_file != null) req.files.add(await http.MultipartFile.fromPath('file', _file!.path));
    var res = await req.send();
    if (res.statusCode == 200 && mounted) Navigator.pop(context);
    setState(() => _ing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("发布")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          TextField(controller: _txt),
          Row(children: [
            IconButton(icon: const Icon(Icons.image), onPressed: () async {
               var f = await _picker.pickImage(source: ImageSource.gallery); setState(() => _file = f);
            }),
            IconButton(icon: const Icon(Icons.videocam), onPressed: () async {
               var f = await _picker.pickVideo(source: ImageSource.gallery); setState(() => _file = f);
            }),
            if (_file != null) const Icon(Icons.check, color: Colors.green)
          ]),
          ElevatedButton(onPressed: _up, child: _ing ? const Text("...") : const Text("发送"))
        ]),
      )
    );
  }
}
