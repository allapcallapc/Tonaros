import 'dart:math';

/// A short random id, unique enough for locally stored sessions/exercises.
String newId() {
  final random = Random();
  return DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
      random.nextInt(1 << 32).toRadixString(36);
}

enum TransitionKind { countdown, tap }

/// What happens between an exercise and the next one.
class Transition {
  const Transition.countdown(this.seconds) : kind = TransitionKind.countdown;
  const Transition.tap()
      : kind = TransitionKind.tap,
        seconds = 0;

  final TransitionKind kind;

  /// Countdown length; always 0 for [TransitionKind.tap].
  final int seconds;

  static const defaultTransition = Transition.countdown(10);

  factory Transition.fromJson(Map<String, dynamic> json) =>
      json['kind'] == 'tap'
          ? const Transition.tap()
          : Transition.countdown(json['seconds'] as int? ?? 0);

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        if (kind == TransitionKind.countdown) 'seconds': seconds,
      };

  @override
  bool operator ==(Object other) =>
      other is Transition && other.kind == kind && other.seconds == seconds;

  @override
  int get hashCode => Object.hash(kind, seconds);
}

/// Fields shared by every exercise type.
sealed class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    required this.sets,
    required this.restBetweenSets,
    required this.transition,
  });

  final String id;
  final String name;
  final int sets;
  final int restBetweenSets;

  /// What follows this exercise in its session; ignored for the last one.
  final Transition transition;

  int get reps;

  Exercise copyWithCommon({
    String? id,
    String? name,
    int? sets,
    int? restBetweenSets,
    Transition? transition,
  });

  Map<String, dynamic> toJson();

  factory Exercise.fromJson(Map<String, dynamic> json) => switch (json['type']) {
        'tempo' => TempoExercise.fromJson(json),
        _ => HoldExercise.fromJson(json),
      };

  Map<String, dynamic> _commonJson() => {
        'id': id,
        'name': name,
        'sets': sets,
        'restBetweenSets': restBetweenSets,
        'transition': transition.toJson(),
      };
}

/// reps × hold, with a rest between reps. Optionally two named holds per
/// rep (e.g. Left/Right): hold 1 → rest → hold 2 → rest → next rep.
class HoldExercise extends Exercise {
  const HoldExercise({
    required super.id,
    required super.name,
    required super.sets,
    required super.restBetweenSets,
    super.transition = Transition.defaultTransition,
    required this.reps,
    required this.holdSeconds,
    required this.restBetweenReps,
    this.twoHolds = false,
    this.firstHoldName = 'Left',
    this.secondHoldName = 'Right',
    this.secondHoldSeconds = 0,
  });

  factory HoldExercise.blank() => HoldExercise(
        id: newId(),
        name: '',
        sets: 1,
        restBetweenSets: 30,
        reps: 10,
        holdSeconds: 5,
        restBetweenReps: 5,
        secondHoldSeconds: 5,
      );

  @override
  final int reps;

  /// Length of the (first) hold.
  final int holdSeconds;
  final int restBetweenReps;
  final bool twoHolds;

  /// Hold names, only used when [twoHolds] is set.
  final String firstHoldName;
  final String secondHoldName;
  final int secondHoldSeconds;

  HoldExercise copyWith({
    String? id,
    String? name,
    int? sets,
    int? restBetweenSets,
    Transition? transition,
    int? reps,
    int? holdSeconds,
    int? restBetweenReps,
    bool? twoHolds,
    String? firstHoldName,
    String? secondHoldName,
    int? secondHoldSeconds,
  }) =>
      HoldExercise(
        id: id ?? this.id,
        name: name ?? this.name,
        sets: sets ?? this.sets,
        restBetweenSets: restBetweenSets ?? this.restBetweenSets,
        transition: transition ?? this.transition,
        reps: reps ?? this.reps,
        holdSeconds: holdSeconds ?? this.holdSeconds,
        restBetweenReps: restBetweenReps ?? this.restBetweenReps,
        twoHolds: twoHolds ?? this.twoHolds,
        firstHoldName: firstHoldName ?? this.firstHoldName,
        secondHoldName: secondHoldName ?? this.secondHoldName,
        secondHoldSeconds: secondHoldSeconds ?? this.secondHoldSeconds,
      );

  @override
  HoldExercise copyWithCommon({
    String? id,
    String? name,
    int? sets,
    int? restBetweenSets,
    Transition? transition,
  }) =>
      copyWith(
        id: id,
        name: name,
        sets: sets,
        restBetweenSets: restBetweenSets,
        transition: transition,
      );

  factory HoldExercise.fromJson(Map<String, dynamic> json) => HoldExercise(
        id: json['id'] as String,
        name: json['name'] as String,
        sets: json['sets'] as int,
        restBetweenSets: json['restBetweenSets'] as int,
        transition: Transition.fromJson(
            json['transition'] as Map<String, dynamic>? ?? const {}),
        reps: json['reps'] as int,
        holdSeconds: json['holdSeconds'] as int,
        restBetweenReps: json['restBetweenReps'] as int,
        twoHolds: json['twoHolds'] as bool? ?? false,
        firstHoldName: json['firstHoldName'] as String? ?? 'Left',
        secondHoldName: json['secondHoldName'] as String? ?? 'Right',
        secondHoldSeconds: json['secondHoldSeconds'] as int? ?? 0,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'hold',
        ..._commonJson(),
        'reps': reps,
        'holdSeconds': holdSeconds,
        'restBetweenReps': restBetweenReps,
        'twoHolds': twoHolds,
        'firstHoldName': firstHoldName,
        'secondHoldName': secondHoldName,
        'secondHoldSeconds': secondHoldSeconds,
      };
}

/// reps × (move → hold → return), back to back with no rest between reps.
class TempoExercise extends Exercise {
  const TempoExercise({
    required super.id,
    required super.name,
    required super.sets,
    required super.restBetweenSets,
    super.transition = Transition.defaultTransition,
    required this.reps,
    required this.moveSeconds,
    required this.holdSeconds,
    required this.returnSeconds,
  });

  factory TempoExercise.blank() => TempoExercise(
        id: newId(),
        name: '',
        sets: 1,
        restBetweenSets: 30,
        reps: 10,
        moveSeconds: 3,
        holdSeconds: 1,
        returnSeconds: 3,
      );

  @override
  final int reps;
  final int moveSeconds;

  /// May be 0 for a move straight into the return.
  final int holdSeconds;
  final int returnSeconds;

  TempoExercise copyWith({
    String? id,
    String? name,
    int? sets,
    int? restBetweenSets,
    Transition? transition,
    int? reps,
    int? moveSeconds,
    int? holdSeconds,
    int? returnSeconds,
  }) =>
      TempoExercise(
        id: id ?? this.id,
        name: name ?? this.name,
        sets: sets ?? this.sets,
        restBetweenSets: restBetweenSets ?? this.restBetweenSets,
        transition: transition ?? this.transition,
        reps: reps ?? this.reps,
        moveSeconds: moveSeconds ?? this.moveSeconds,
        holdSeconds: holdSeconds ?? this.holdSeconds,
        returnSeconds: returnSeconds ?? this.returnSeconds,
      );

  @override
  TempoExercise copyWithCommon({
    String? id,
    String? name,
    int? sets,
    int? restBetweenSets,
    Transition? transition,
  }) =>
      copyWith(
        id: id,
        name: name,
        sets: sets,
        restBetweenSets: restBetweenSets,
        transition: transition,
      );

  factory TempoExercise.fromJson(Map<String, dynamic> json) => TempoExercise(
        id: json['id'] as String,
        name: json['name'] as String,
        sets: json['sets'] as int,
        restBetweenSets: json['restBetweenSets'] as int,
        transition: Transition.fromJson(
            json['transition'] as Map<String, dynamic>? ?? const {}),
        reps: json['reps'] as int,
        moveSeconds: json['moveSeconds'] as int,
        holdSeconds: json['holdSeconds'] as int,
        returnSeconds: json['returnSeconds'] as int,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'tempo',
        ..._commonJson(),
        'reps': reps,
        'moveSeconds': moveSeconds,
        'holdSeconds': holdSeconds,
        'returnSeconds': returnSeconds,
      };
}

/// An ordered list of exercises, run one after another.
class Session {
  const Session({required this.id, required this.name, required this.exercises});

  final String id;
  final String name;
  final List<Exercise> exercises;

  Session copyWith({String? id, String? name, List<Exercise>? exercises}) =>
      Session(
        id: id ?? this.id,
        name: name ?? this.name,
        exercises: exercises ?? this.exercises,
      );

  /// A copy with fresh ids throughout, so it's fully independent.
  Session duplicate(String newName) => Session(
        id: newId(),
        name: newName,
        exercises: [for (final e in exercises) e.copyWithCommon(id: newId())],
      );

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        id: json['id'] as String,
        name: json['name'] as String,
        exercises: [
          for (final e in json['exercises'] as List)
            Exercise.fromJson(e as Map<String, dynamic>),
        ],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'exercises': [for (final e in exercises) e.toJson()],
      };
}
