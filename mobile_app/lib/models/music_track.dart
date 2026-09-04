class MusicTrack {
  final int id;
  final String title;
  final String? description;
  final String filename;
  final int filesize;
  final String checksum;

  MusicTrack({
    required this.id,
    required this.title,
    required this.description,
    required this.filename,
    required this.filesize,
    required this.checksum,
  });

  factory MusicTrack.fromJson(Map<String, dynamic> json) => MusicTrack(
        id: json['id'] as int,
        title: json['title'] as String,
        description: json['description'] as String?,
        filename: json['filename'] as String? ?? 'audio.mp3',
        filesize: json['filesize'] as int? ?? 0,
        checksum: json['checksum_sha256'] as String? ?? '',
      );
}
