use strict;

use JSON;
use Data::Dumper;
use LWP::UserAgent;
use Eldhelm::Util::FileSystem;
use Eldhelm::Util::CommandLine;

my $cmd = Eldhelm::Util::CommandLine->new(
	argv => \@ARGV,

	# items   => [ 'exmplain what should be listed here' ],
	options => [
		[ 'h help', 'this help text' ],
		[ 'd',      'device by name' ],
		[ 'g',      'group by name' ],
		[ 'on',     'on' ],
		[ 'off',    'off' ],
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

sub output($) {
	my ($str) = @_;
	return unless $args{debug};
	print "$str\n";
}

my $token = $args{s};

sub callApiPost {
	my ($url, $data) = @_;
	my $host    = "$config->{host}$url";
	my $content = encode_json($data);
	output($host);
	output($content);

	my $req = HTTP::Request->new('POST', $host);
	$req->content_type('application/json');
	$req->header(authorization => $token) if $token;
	$req->content($content);

	my $ua       = LWP::UserAgent->new;
	my $response = $ua->request($req);
	if ($response->is_success) {
		output($response->content);
		return decode_json($response->content);
	} else {
		die $response->status_line.": $url";
	}
}

sub callApiGet {
	my ($url, $data) = @_;
	my $host = "$config->{host}$url";
	output($host);
	$host .= join('&', map { "$_=$data->{$_}" } keys %$data) if $data;

	my $req = HTTP::Request->new('GET', $host);
	$req->content_type('application/json');
	$req->header(authorization => $token) if $token;

	my $ua       = LWP::UserAgent->new;
	my $response = $ua->request($req);
	if ($response->is_success) {
		output($response->content);
		return decode_json($response->content);
	} else {
		die $response->status_line.": $url";
	}
}

my $groups;

sub getGroups() {
	return @$groups if $groups;
	return @{ $groups = callApiGet('/services/groups') };
}

sub groupByName {
	my ($name) = @_;
	return (grep { $_->{name} =~ /$name/i } getGroups)[0];
}

sub findGroupId {
	my ($name) = @_;
	return groupByName($args{g})->{groupId};
}

my $devices;

sub getDevices() {
	return @$devices if $devices;
	return @{ $devices = callApiGet('/services/devices') };
}

sub deviceByName {
	my ($name) = @_;
	return (grep { $_->{name} =~ /$name/i } getDevices)[0];
}

sub findDeviceId {
	my ($name) = @_;
	return deviceByName($args{d})->{deviceId};
}

unless ($token) {
	my $authData = callApiPost(
		'/services/session',
		{   username     => $config->{username},
			password     => $config->{password},
			serialNumber => $config->{serialNumber}
		}
	);
	$token = $authData->{securityToken};
	die 'authentication failed' unless $token;
}

if ($args{on}) {
	callApiGet('/services/group/set?idx='.findGroupId($args{g}).'&onoff=1')   if $args{g};
	callApiGet('/services/device/set?idx='.findDeviceId($args{d}).'&onoff=1') if $args{d};
} elsif ($args{off}) {
	callApiGet('/services/group/set?idx='.findGroupId($args{g}).'&onoff=0')   if $args{g};
	callApiGet('/services/device/set?idx='.findDeviceId($args{d}).'&onoff=0') if $args{d};
}
