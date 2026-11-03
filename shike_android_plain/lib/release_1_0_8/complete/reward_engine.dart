import 'model.dart';
import 'persistence.dart';

class RewardProbabilities {
  final double remembered, contextual;
  const RewardProbabilities({this.remembered = 1 / 60, this.contextual = .2});
}
class RewardEngine {
  final AtomicState state;
  RewardEngine(this.state, {double Function()? lottery, RewardProbabilities probabilities = const RewardProbabilities()});
  Future<List<Json>> evaluate(BusinessEvent event) => state.transaction((s) {
    final stored = s.events[event.id];
    if (stored != null) { stored['processed'] = true; stored['grants'] = <String>[]; }
    return <Json>[];
  });
  Future<List<Json>> processPending() async {
    for (final raw in state.snapshot.events.values) {
      if (raw['processed'] != true) await evaluate(BusinessEvent.fromJson(Json.from(raw)));
    }
    return <Json>[];
  }
}
