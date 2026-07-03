enum RouteDecision {
  shell,
  native,
  undecided;

  static RouteDecision parse(String? raw) {
    switch (raw) {
      case 'shell':
        return RouteDecision.shell;
      case 'native':
        return RouteDecision.native;
      default:
        return RouteDecision.undecided;
    }
  }

  String persistToken() {
    switch (this) {
      case RouteDecision.shell:
        return 'shell';
      case RouteDecision.native:
        return 'native';
      case RouteDecision.undecided:
        return 'undecided';
    }
  }
}
