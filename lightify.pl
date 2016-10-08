use strict;

use JSON;
use Data::Dumper;
use Eldhelm::Util::CommandLine;
use Eldhelm::Util::FileSystem;
use Osram::Lightify;

my $cmd = Eldhelm::Util::CommandLine->new(
	argv => \@ARGV,

	# items   => [ 'exmplain what should be listed here' ],
	options => [
		[ 'h help', 'this help text' ],
		[ 'd',      'device by name' ],
		[ 'g',      'group by name' ],
		[ 'on',     'on' ],
		[ 'off',    'off' ],
		[ 'lg',     'list groups' ],
		[ 'ld',     'list devices' ],
		[ 'debug',  'shows messages' ],
		[ 's',      'security token' ]
	]
);

my %args = $cmd->arguments;

if ($args{h} || $args{help}) {
	print $cmd->usage;
	exit;
}

my $cfgStream = Eldhelm::Util::FileSystem->getFileContents('config.json');
my $config    = decode_json($cfgStream);

my $api = Osram::Lightify->new(%$config, debug => $args{debug}, token => $args{s});

unless ($api->{token}) {
	$api->authenticate;
	die 'Authentication failed' unless $api->{token};
}

if ($args{on}) {
	$api->callApiGet('/services/group/set?idx='.$api->findGroupId($args{g}).'&onoff=1')   if $args{g};
	$api->callApiGet('/services/device/set?idx='.$api->findDeviceId($args{d}).'&onoff=1') if $args{d};
} elsif ($args{off}) {
	$api->callApiGet('/services/group/set?idx='.$api->findGroupId($args{g}).'&onoff=0')   if $args{g};
	$api->callApiGet('/services/device/set?idx='.$api->findDeviceId($args{d}).'&onoff=0') if $args{d};
}

if ($args{lg}) {
	warn Dumper $api->getGroups;
}

if ($args{ld}) {
	warn Dumper $api->getDevices;
}
