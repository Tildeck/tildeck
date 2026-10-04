/// The operating system a host runs, for its icon: detected over SSH the
/// first time it connects, or chosen in the host's editor.
enum HostOs {
  linux('Linux'),
  ubuntu('Ubuntu'),
  debian('Debian'),
  fedora('Fedora'),
  centos('CentOS'),
  redhat('Red Hat'),
  rocky('Rocky Linux'),
  alma('AlmaLinux'),
  alpine('Alpine Linux'),
  arch('Arch Linux'),
  manjaro('Manjaro'),
  opensuse('openSUSE'),
  mint('Linux Mint'),
  kali('Kali Linux'),
  nixos('NixOS'),
  gentoo('Gentoo'),
  freebsd('FreeBSD'),
  openbsd('OpenBSD'),
  macos('macOS'),
  windows('Windows');

  const HostOs(this.title);

  /// The system's own name, the same in every language.
  final String title;
}

/// Run once on a separate exec channel: os-release on Linux and the BSDs,
/// else the kernel's name, else (in Windows' cmd) its version line.
const osCommand = 'cat /etc/os-release 2>/dev/null || uname -s 2>/dev/null || ver';

/// What [osCommand] printed, as a system; null when it is not one known.
HostOs? parseOs(String output) {
  final text = output.trim();
  if (text.isEmpty) return null;
  if (text.contains('Microsoft Windows') || text.contains('is not recognized as an internal or external command')) {
    return HostOs.windows;
  }
  final fields = <String, String>{};
  for (final line in text.split('\n')) {
    final at = line.indexOf('=');
    if (at <= 0) continue;
    var value = line.substring(at + 1).trim();
    if (value.length >= 2 && (value.startsWith('"') || value.startsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }
    fields[line.substring(0, at).trim()] = value.toLowerCase();
  }
  if (fields.containsKey('ID')) {
    // The distribution itself, else the nearest one it is like.
    for (final id in [fields['ID']!, ...?fields['ID_LIKE']?.split(RegExp(r'\s+'))]) {
      final os = _byId(id);
      if (os != null) return os;
    }
    return HostOs.linux;
  }
  return switch (text.split('\n').first.trim()) {
    'Linux' => HostOs.linux,
    'Darwin' => HostOs.macos,
    'FreeBSD' => HostOs.freebsd,
    'OpenBSD' => HostOs.openbsd,
    _ => null,
  };
}

HostOs? _byId(String id) => switch (id) {
  'ubuntu' || 'pop' || 'elementary' || 'zorin' => HostOs.ubuntu,
  'debian' || 'raspbian' => HostOs.debian,
  'fedora' => HostOs.fedora,
  'centos' => HostOs.centos,
  'rhel' => HostOs.redhat,
  'rocky' => HostOs.rocky,
  'almalinux' => HostOs.alma,
  'alpine' => HostOs.alpine,
  'arch' || 'archarm' => HostOs.arch,
  'manjaro' || 'manjaro-arm' => HostOs.manjaro,
  'linuxmint' => HostOs.mint,
  'kali' => HostOs.kali,
  'nixos' => HostOs.nixos,
  'gentoo' => HostOs.gentoo,
  'freebsd' => HostOs.freebsd,
  'openbsd' => HostOs.openbsd,
  _ when id == 'suse' || id == 'sles' || id.startsWith('opensuse') => HostOs.opensuse,
  _ => null,
};
