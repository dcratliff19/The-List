/// Navigation destinations are distinct from persisted entity kinds and flags.
enum WorkspaceSection {
  projects('All projects'),
  today('Today'),
  inbox('Inbox'),
  reminders('Reminders'),
  feed('Shared activity'),
  favorites('Favorites'),
  archive('Archive');

  final String title;
  const WorkspaceSection(this.title);

  static const mobileDestinations = [projects, today, inbox, reminders, feed];
}
