/// Immutable data models representing the digitized engineering graphics curriculum.
library;

class Chapter {
  const Chapter({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.dirFile,
  });

  final String id;
  final String title;
  final String subtitle;
  final String dirFile;

  factory Chapter.fromJson(Map<String, dynamic> json) {
    return Chapter(
      id: json['id'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String,
      dirFile: json['dirFile'] as String? ?? '',
    );
  }
}

class SolutionStep {
  const SolutionStep({
    required this.index,
    required this.title,
    required this.image,
    required this.note,
  });

  final int index;
  final String title;
  final String image;
  final String note;

  factory SolutionStep.fromJson(Map<String, dynamic> json) {
    return SolutionStep(
      index: (json['index'] as num).toInt(),
      title: json['title'] as String,
      image: json['image'] as String,
      note: (json['note'] as String? ?? '').trim(),
    );
  }
}

class VideoResource {
  const VideoResource({
    required this.asset,
    required this.sourceAvi,
    required this.sizeBytes,
  });

  final String asset;
  final String sourceAvi;
  final int sizeBytes;

  factory VideoResource.fromJson(Map<String, dynamic> json) {
    return VideoResource(
      asset: json['asset'] as String,
      sourceAvi: json['sourceAvi'] as String? ?? '',
      sizeBytes: (json['sizeBytes'] as num? ?? 0).toInt(),
    );
  }
}

enum JietiMode {
  stepped,
  tabbed,
  twoState;

  static JietiMode fromWire(String value) {
    return switch (value) {
      'tabbed' => JietiMode.tabbed,
      'stepped' => JietiMode.stepped,
      _ => JietiMode.twoState,
    };
  }
}

class Problem {
  const Problem({
    required this.id,
    required this.chapterId,
    required this.groupIndex,
    required this.orderInChapter,
    required this.page,
    required this.no,
    required this.displayLabel,
    required this.statement,
    required this.subjectImage,
    required this.answerImage,
    required this.jietiMode,
    required this.steps,
    required this.video,
  });

  final String id;
  final String chapterId;
  final int groupIndex;
  final int orderInChapter;
  final int page;
  final String no;
  final String displayLabel;
  final String statement;
  final String subjectImage;
  final String answerImage;
  final JietiMode jietiMode;
  final List<SolutionStep> steps;
  final VideoResource? video;

  bool get hasVideo => video != null;

  bool get hasMultiStep => steps.length > 2;

  String get shortCode => 'P$page · No.$no';

  bool matchesQuery(String rawQuery, String chapterTitle) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    final cleanNum = q.replaceAll(RegExp(r'^[pP第页\s]+'), '');
    if (page.toString() == cleanNum) return true;
    if (displayLabel.toLowerCase().contains(q)) return true;
    if (shortCode.toLowerCase().contains(q)) return true;
    if (id.toLowerCase().contains(q)) return true;
    if (statement.toLowerCase().contains(q)) return true;
    if (chapterTitle.toLowerCase().contains(q)) return true;
    for (final s in steps) {
      if (s.note.toLowerCase().contains(q) || s.title.toLowerCase().contains(q)) {
        return true;
      }
    }
    return false;
  }

  factory Problem.fromJson(Map<String, dynamic> json) {
    final stepsJson = (json['steps'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final videoJson = json['video'] as Map<String, dynamic>?;
    return Problem(
      id: json['id'] as String,
      chapterId: json['chapterId'] as String,
      groupIndex: (json['groupIndex'] as num).toInt(),
      orderInChapter: (json['orderInChapter'] as num).toInt(),
      page: (json['page'] as num).toInt(),
      no: json['no'] as String,
      displayLabel: json['displayLabel'] as String,
      statement: (json['statement'] as String? ?? '').trim(),
      subjectImage: json['subjectImage'] as String,
      answerImage: json['answerImage'] as String,
      jietiMode: JietiMode.fromWire(json['jietiMode'] as String? ?? ''),
      steps: stepsJson.map(SolutionStep.fromJson).toList(growable: false),
      video: videoJson == null ? null : VideoResource.fromJson(videoJson),
    );
  }
}

class Curriculum {
  const Curriculum({
    required this.schemaVersion,
    required this.chapters,
    required this.problems,
  });

  final int schemaVersion;
  final List<Chapter> chapters;
  final List<Problem> problems;

  List<Problem> problemsInChapter(String chapterId) =>
      problems.where((p) => p.chapterId == chapterId).toList(growable: false);

  Chapter chapterById(String chapterId) =>
      chapters.firstWhere((c) => c.id == chapterId);

  Problem? findById(String id) {
    for (final p in problems) {
      if (p.id == id) return p;
    }
    return null;
  }

  factory Curriculum.fromJson(Map<String, dynamic> json) {
    final chaptersJson = (json['chapters'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final problemsJson = (json['problems'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    return Curriculum(
      schemaVersion: (json['schemaVersion'] as num? ?? 1).toInt(),
      chapters: chaptersJson.map(Chapter.fromJson).toList(growable: false),
      problems: problemsJson.map(Problem.fromJson).toList(growable: false),
    );
  }
}
