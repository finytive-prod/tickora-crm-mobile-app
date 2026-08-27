void main() {
  final lower = 'rec_outgoing_1234_romi.m4a'.toLowerCase();
  print('inbound: ${lower.contains('inbound')}');
  print('incoming: ${lower.contains('incoming')}');
  print('_in_: ${lower.contains('_in_')}');
  print('_inc_: ${lower.contains('_inc_')}');
  print('callin: ${lower.contains('callin')}');
  print('recv: ${lower.contains('recv')}');
  print('received: ${lower.contains('received')}');
  print('(in): ${lower.contains('(in)')}');
  print('in_: ${lower.contains('in_')}');
  print('inc_: ${lower.contains('inc_')}');
}
