import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

// ─────────────────────────────────────────────
// KONFIGURASI BASE URL
// Emulator Android  → 10.0.2.2
// Device Fisik      → ganti dengan IP komputer, misal 192.168.1.x
// ─────────────────────────────────────────────
const String baseUrl = 'https://tugas-232013-production.up.railway.app';

// ─────────────────────────────────────────────
// HELPER: Buat MultipartFile yang kompatibel (REVISI FINAL)
// ─────────────────────────────────────────────
Future<http.MultipartFile> buildMultipartFile(
  XFile file,
  String fieldName,
) async {
  final ext = file.name.split('.').last.toLowerCase();

  // Tentukan MIME type
  String mimeType;
  String mimeSubtype;
  if (['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext)) {
    mimeType = 'image';
    mimeSubtype = ext == 'jpg' ? 'jpeg' : ext;
  } else {
    mimeType = 'video';
    mimeSubtype = ext;
  }
  final contentType = MediaType(mimeType, mimeSubtype);

  if (kIsWeb) {
    // FLUTTER WEB SOLUSI: Gunakan Stream (openRead) agar tidak 0 Byte
    // Ini akan membaca file secara bertahap tanpa membuat RAM browser jebol
    final stream = file.openRead();
    final length = await file.length();
    
    return http.MultipartFile(
      fieldName,
      stream,
      length,
      filename: file.name,
      contentType: contentType,
    );
  } else {
    // Mobile/Desktop: pakai fromPath (efisien, tidak load ke RAM)
    return await http.MultipartFile.fromPath(
      fieldName,
      file.path,
      filename: file.name,
      contentType: contentType,
    );
  }
}

void main() {
  runApp(const MyApp());
}

// ═══════════════════════════════════════════
//  ROOT APP
// ═══════════════════════════════════════════
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Media Player 232013',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B5D7A)),
        scaffoldBackgroundColor: const Color(0xFFF4F7FB),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

// ═══════════════════════════════════════════
//  MODEL
// ═══════════════════════════════════════════
class MediaItem {
  final int id;
  final String title;
  final String thumbnail;
  final String video;

  const MediaItem({
    required this.id,
    required this.title,
    required this.thumbnail,
    required this.video,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: int.tryParse(json['id'].toString()) ?? 0,
      title: json['title'] ?? '',
      thumbnail: json['thumbnail'] ?? '',
      video: json['video'] ?? '',
    );
  }

  /// URL lengkap thumbnail dari server
  String get thumbnailUrl => thumbnail.startsWith('http')
      ? thumbnail
      : '$baseUrl/thumbnail/$thumbnail';

  /// URL lengkap video dari server
  String get videoUrl => video.startsWith('http')
      ? video
      : '$baseUrl/video/$video';
}

// ═══════════════════════════════════════════
//  HOME PAGE – Daftar Thumbnail
// ═══════════════════════════════════════════
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<MediaItem> _mediaList = [];
  bool _isLoading = true;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _fetchMedia();
  }

  // Ambil semua data dari API
  Future<void> _fetchMedia() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api.php?action=list'))
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _mediaList = data.map((e) => MediaItem.fromJson(e)).toList();
        });
      } else {
        setState(() => _errorMsg = 'Server error: ${response.statusCode}');
      }
    } catch (e) {
      setState(
        () => _errorMsg =
            'Gagal terhubung ke server.\nCek baseUrl & pastikan Laragon aktif.\n$e',
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Navigasi ke halaman tambah, refresh jika data baru disimpan
  Future<void> _goToAddPage() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddMediaPage()),
    );
    if (saved == true) _fetchMedia();
  }

  // Navigasi ke halaman edit
  Future<void> _goToEditPage(MediaItem item) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EditMediaPage(item: item)),
    );
    if (saved == true) _fetchMedia();
  }

  // Hapus media dengan konfirmasi
  Future<void> _deleteMedia(MediaItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Media'),
        content: Text(
          'Apakah Anda yakin ingin menghapus "${item.title}"?\nTindakan ini tidak dapat dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Hapus',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api.php?action=delete&id=${item.id}'),
      );

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body['success'] == true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Media berhasil dihapus')),
            );
            _fetchMedia();
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Gagal: ${body['message'] ?? 'Unknown error'}'),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Server error: ${response.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F7FB),
        foregroundColor: const Color(0xFF1F2937),
        centerTitle: true,
        elevation: 0,
        title: const Text(
          'Media Player',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchMedia),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _goToAddPage,
        backgroundColor: const Color(0xFF0B5D7A),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0B5D7A)),
      );
    }

    if (_errorMsg != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 580),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFDA4AF)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFF9F1239),
                  size: 42,
                ),
                const SizedBox(height: 10),
                Text(
                  _errorMsg!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF9F1239),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: _fetchMedia,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Coba Lagi'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0B5D7A),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_mediaList.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.video_library_outlined,
              color: Color(0xFF94A3B8),
              size: 64,
            ),
            SizedBox(height: 12),
            Text(
              'Belum ada media.\nTekan + untuk menambah.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isWide = constraints.maxWidth >= 720;

        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: _mediaList.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isWide ? 2 : 1,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 300,
          ),
          itemBuilder: (context, index) => _MediaCard(
            item: _mediaList[index],
            onEdit: () => _goToEditPage(_mediaList[index]),
            onDelete: () => _deleteMedia(_mediaList[index]),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
//  Kartu Thumbnail
// ─────────────────────────────────────────────
class _MediaCard extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MediaCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  String get _sourceLabel => 'Video Database';

  // Tinggi bagian info teks di bawah gambar
  static const double _infoHeight = 76.0;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => VideoPlayerPage(item: item)),
        ),
        onLongPress: () => _showContextMenu(context),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double imageHeight = constraints.maxHeight - _infoHeight;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: imageHeight,
                  child: Image.network(
                    item.thumbnailUrl,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFFE2E8F0),
                      child: const Icon(
                        Icons.broken_image,
                        color: Color(0xFF94A3B8),
                        size: 40,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: _infoHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _sourceLabel,
                          style: Theme.of(
                            context,
                          ).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0B5D7A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.video,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF64748B),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFD6DFEA),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.edit,
                  color: Color(0xFF0B5D7A),
                ),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(context);
                  onEdit();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete,
                  color: Color(0xFFDC2626),
                ),
                title: const Text(
                  'Hapus',
                  style: TextStyle(color: Color(0xFFDC2626)),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onDelete();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
//  ADD MEDIA PAGE – Form Input
// ═══════════════════════════════════════════
class AddMediaPage extends StatefulWidget {
  const AddMediaPage({super.key});

  @override
  State<AddMediaPage> createState() => _AddMediaPageState();
}

class _AddMediaPageState extends State<AddMediaPage> {
  final _titleController = TextEditingController();
  XFile? _thumbnailFile;
  XFile? _videoFile;
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  // Pilih gambar dari galeri
  Future<void> _pickThumbnail() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked != null) {
      setState(() => _thumbnailFile = picked);
    }
  }

  // Pilih file video
  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _videoFile = picked);
    }
  }

  // Simpan ke server via multipart POST
  Future<void> _save() async {
    final title = _titleController.text.trim();

    if (title.isEmpty) {
      _showSnack('Title tidak boleh kosong!');
      return;
    }
    if (_thumbnailFile == null) {
      _showSnack('Pilih thumbnail terlebih dahulu!');
      return;
    }
    if (_videoFile == null) {
      _showSnack('Pilih file video terlebih dahulu!');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api.php?action=add'),
      );
      request.fields['title'] = title;
      request.files.add(await buildMultipartFile(_thumbnailFile!, 'thumbnail'));
      request.files.add(await buildMultipartFile(_videoFile!, 'video'));

      final streamed = await request.send().timeout(
        const Duration(minutes: 5),
      );
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body['success'] == true) {
          if (mounted) Navigator.pop(context, true);
        } else {
          _showSnack('Gagal: ${body['message'] ?? 'Unknown error'}');
        }
      } else {
        _showSnack('Server error: ${response.statusCode}');
      }
    } catch (e) {
      _showSnack('Koneksi gagal: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F7FB),
        foregroundColor: const Color(0xFF1F2937),
        elevation: 0,
        centerTitle: true,
        title: const Text('Tambah Media'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Field Title ──
            _label('Title'),
            const SizedBox(height: 6),
            TextField(
              controller: _titleController,
              style: const TextStyle(color: Color(0xFF1F2937)),
              decoration: _inputDecoration('Masukkan judul video'),
            ),
            const SizedBox(height: 20),

            // ── Pilih Thumbnail ──
            _label('Thumbnail'),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pickThumbnail,
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFD6DFEA)),
                ),
                clipBehavior: Clip.antiAlias,
                child: _thumbnailFile != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          FutureBuilder<Uint8List>(
                            future: _thumbnailFile!.readAsBytes(),
                            builder: (context, snapshot) {
                              if (snapshot.hasData) {
                                return Image.memory(
                                  snapshot.data!,
                                  fit: BoxFit.cover,
                                );
                              } else if (snapshot.hasError) {
                                return const Center(
                                  child: Icon(
                                    Icons.error_outline,
                                    color: Colors.redAccent,
                                    size: 40,
                                  ),
                                );
                              }
                              return const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              );
                            },
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: const EdgeInsets.all(4),
                              child: const Icon(
                                Icons.edit,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 52,
                            color: Color(0xFF0B5D7A),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Tap untuk pilih gambar',
                            style: TextStyle(color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Pilih File Video ──
            _label('File Video'),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pickVideo,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFD6DFEA)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _videoFile == null
                                  ? 'Tap untuk pilih video'
                                  : 'File terpilih',
                              style: TextStyle(
                                color: _videoFile == null
                                    ? const Color(0xFF64748B)
                                    : const Color(0xFF475569),
                                fontSize: 12,
                              ),
                            ),
                            if (_videoFile != null)
                              Text(
                                _videoFile!.name,
                                style: const TextStyle(
                                  color: Color(0xFF1F2937),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Icon(
                        _videoFile == null
                            ? Icons.video_library_outlined
                            : Icons.check_circle,
                        color: _videoFile == null
                            ? const Color(0xFF0B5D7A)
                            : const Color(0xFF16A34A),
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // ── Tombol Simpan ──
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0B5D7A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Simpan',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      color: Color(0xFF334155),
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
  );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFD6DFEA)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFD6DFEA)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF0B5D7A)),
    ),
  );
}

// ═══════════════════════════════════════════
//  EDIT MEDIA PAGE – Form Edit Data
// ═══════════════════════════════════════════
class EditMediaPage extends StatefulWidget {
  final MediaItem item;
  const EditMediaPage({super.key, required this.item});

  @override
  State<EditMediaPage> createState() => _EditMediaPageState();
}

class _EditMediaPageState extends State<EditMediaPage> {
  late final TextEditingController _titleController;
  XFile? _thumbnailFile;
  XFile? _videoFile;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.item.title);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  // Pilih gambar dari galeri
  Future<void> _pickThumbnail() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked != null) {
      setState(() => _thumbnailFile = picked);
    }
  }

  // Pilih file video
  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _videoFile = picked);
    }
  }

  // Update data ke server
  Future<void> _save() async {
    final title = _titleController.text.trim();

    if (title.isEmpty) {
      _showSnack('Title tidak boleh kosong!');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api.php?action=update&id=${widget.item.id}'),
      );
      request.fields['title'] = title;

      // Jika thumbnail dipilih, upload yang baru
      if (_thumbnailFile != null) {
        request.files.add(await buildMultipartFile(_thumbnailFile!, 'thumbnail'));
      }

      // Jika video dipilih, upload yang baru
      if (_videoFile != null) {
        request.files.add(await buildMultipartFile(_videoFile!, 'video'));
      }

      final streamed = await request.send().timeout(
        const Duration(minutes: 5),
      );
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body['success'] == true) {
          if (mounted) Navigator.pop(context, true);
        } else {
          _showSnack('Gagal: ${body['message'] ?? 'Unknown error'}');
        }
      } else {
        _showSnack('Server error: ${response.statusCode}');
      }
    } catch (e) {
      _showSnack('Koneksi gagal: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F7FB),
        foregroundColor: const Color(0xFF1F2937),
        elevation: 0,
        centerTitle: true,
        title: const Text('Edit Media'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Field Title ──
            _label('Title'),
            const SizedBox(height: 6),
            TextField(
              controller: _titleController,
              style: const TextStyle(color: Color(0xFF1F2937)),
              decoration: _inputDecoration('Masukkan judul video'),
            ),
            const SizedBox(height: 20),

            // ── Pilih Thumbnail (Opsional) ──
            _label('Thumbnail (Opsional - Biarkan kosong jika tidak ingin ubah)'),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pickThumbnail,
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFD6DFEA)),
                ),
                clipBehavior: Clip.antiAlias,
                child: _thumbnailFile != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          FutureBuilder<Uint8List>(
                            future: _thumbnailFile!.readAsBytes(),
                            builder: (context, snapshot) {
                              if (snapshot.hasData) {
                                return Image.memory(
                                  snapshot.data!,
                                  fit: BoxFit.cover,
                                );
                              } else if (snapshot.hasError) {
                                return const Center(
                                  child: Icon(
                                    Icons.error_outline,
                                    color: Colors.redAccent,
                                    size: 40,
                                  ),
                                );
                              }
                              return const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              );
                            },
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: const EdgeInsets.all(4),
                              child: const Icon(
                                Icons.edit,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(
                            Icons.image,
                            size: 52,
                            color: Color(0xFF0B5D7A),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Tap untuk ubah gambar',
                            style: TextStyle(color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Pilih File Video (Opsional) ──
            _label('File Video (Opsional - Biarkan kosong jika tidak ingin ubah)'),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pickVideo,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFD6DFEA)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _videoFile == null
                                  ? 'Tap untuk ubah video'
                                  : 'File terpilih',
                              style: TextStyle(
                                color: _videoFile == null
                                    ? const Color(0xFF64748B)
                                    : const Color(0xFF475569),
                                fontSize: 12,
                              ),
                            ),
                            if (_videoFile != null)
                              Text(
                                _videoFile!.name,
                                style: const TextStyle(
                                  color: Color(0xFF1F2937),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Icon(
                        _videoFile == null
                            ? Icons.video_library_outlined
                            : Icons.check_circle,
                        color: _videoFile == null
                            ? const Color(0xFF0B5D7A)
                            : const Color(0xFF16A34A),
                        size: 24,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // ── Tombol Simpan ──
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0B5D7A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Perbarui',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      color: Color(0xFF334155),
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
  );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFD6DFEA)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFD6DFEA)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF0B5D7A)),
    ),
  );
}

// ═══════════════════════════════════════════
//  VIDEO PLAYER PAGE – File Video Player
// ═══════════════════════════════════════════
class VideoPlayerPage extends StatefulWidget {
  final MediaItem item;
  const VideoPlayerPage({super.key, required this.item});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final VideoPlayerController _controller;
  late final Future<void> _initializeVideoPlayerFuture;

  @override
  void initState() {
    super.initState();
    // Tetap memakai URL video dari database
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.item.videoUrl),
    );
    _initializeVideoPlayerFuture = _controller.initialize().then((_) {
      _controller.addListener(() {
        if (mounted) setState(() {});
      });
    });
    _controller.setLooping(false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
  }

  String _formatDuration(Duration d) {
    String pad(int n) => n.toString().padLeft(2, '0');
    final m = pad(d.inMinutes.remainder(60));
    final s = pad(d.inSeconds.remainder(60));
    return d.inHours > 0 ? '${pad(d.inHours)}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F7FB),
        foregroundColor: const Color(0xFF1F2937),
        elevation: 0,
        title: Text(
          widget.item.title,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: _buildVideoPlayer(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    final Duration position = _controller.value.position;
    final Duration total = _controller.value.duration;
    final double progress = total.inMilliseconds > 0
        ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return FutureBuilder<void>(
      future: _initializeVideoPlayerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AspectRatio(
            aspectRatio: 16 / 9,
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFF0B5D7A)),
            ),
          );
        }

        if (snapshot.hasError) {
          return AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDA4AF)),
              ),
              child: Center(
                child: Text(
                  'Gagal memuat video.\n\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF9F1239),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }

        final double aspectRatio = _controller.value.aspectRatio > 0
            ? _controller.value.aspectRatio
            : 16 / 9;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _togglePlayback,
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_controller),
                    if (!_controller.value.isPlaying)
                      Container(
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(14),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 44,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFD6DFEA)),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _togglePlayback,
                    icon: Icon(
                      _controller.value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: const Color(0xFF1F2937),
                      size: 26,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 10,
                        ),
                        activeTrackColor: const Color(0xFF0B5D7A),
                        inactiveTrackColor: const Color(0xFFD1D9E6),
                        thumbColor: const Color(0xFF0B5D7A),
                        overlayColor: const Color(0x330B5D7A),
                      ),
                      child: Slider(
                        value: progress,
                        onChanged: (v) {
                          if (total.inMilliseconds <= 0) return;
                          _controller.seekTo(
                            Duration(
                              milliseconds: (v * total.inMilliseconds).round(),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_formatDuration(position)} / ${_formatDuration(total)}',
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}