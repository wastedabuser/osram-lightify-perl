package Osram::Lightify;

use JSON;
use LWP::UserAgent;
use HTTP::Request;

sub new {
	my ($class, %args) = @_;
	my $self = {%args};
	bless $self, $class;

	return $self;
}

sub output {
	my ($self, $str) = @_;
	return unless $self->{debug};
	return $self->{outputSub}->($str) if $self->{outputSub};
	print "$str\n";
}

sub authenticate {
	my ($self) = @_;
	my $result = $self->callApiPost(
		'/services/session',
		{   username     => $self->{username},
			password     => $self->{password},
			serialNumber => $self->{serialNumber}
		}
	);
	$self->{token} = $result->{securityToken};
	return $result;
}

sub callApiPost {
	my ($self, $url, $data) = @_;
	my $host    = "$self->{host}$url";
	my $content = encode_json($data);
	$self->output('========= API post =========');
	$self->output($host);
	$self->output($content);

	my $req = HTTP::Request->new('POST', $host);
	$req->content_type('application/json');
	$req->header(authorization => $self->{token}) if $self->{token};
	$req->content($content);

	my $ua       = LWP::UserAgent->new;
	my $response = $ua->request($req);
	if ($response->is_success) {
		$self->output($response->content);
		return decode_json($response->content);
	} else {
		die $response->status_line.": $url";
	}
}

sub callApiGet {
	my ($self, $url, $data) = @_;
	my $host = "$self->{host}$url";
	$self->output('========= API get =========');
	$self->output($host);
	$host .= join('&', map { "$_=$data->{$_}" } keys %$data) if $data;

	my $req = HTTP::Request->new('GET', $host);
	$req->content_type('application/json');
	$req->header(authorization => $self->{token}) if $self->{token};

	my $ua       = LWP::UserAgent->new;
	my $response = $ua->request($req);
	if ($response->is_success) {
		$self->output($response->content);
		return decode_json($response->content);
	} else {
		die $response->status_line.": $url";
	}
}

# gruops
# =======================================

sub allGroups {
	my ($self) = @_;
	return @{ $self->{groups} } if $self->{groups};
	return @{ $self->{groups} = $self->callApiGet('/services/groups') };
}

sub group {
	my ($self, $name) = @_;
	return (grep { $_->{name} =~ /$name/i } $self->allGroups)[0];
}

sub groupId {
	my ($self, $name) = @_;
	return $self->group($name)->{groupId};
}

sub groupToggle {
	my ($self, $name, $state, $level, $time) = @_;
	my %params = (
		idx   => $self->groupId($name),
		onoff => $state || 0,
		time  => $time || 0,
	);
	$params{level} = $level if $level;
	$self->callApiGet('/services/group/set?'.$self->compileParams(%params));
}

sub groupLevel {
	my ($self, $name, $level, $time) = @_;
	my %params = (
		idx   => $self->groupId($name),
		level => $level || 0,
		time  => $time || 0,
	);
	$self->callApiGet('/services/group/set?'.$self->compileParams(%params));
}

sub groupTemp {
	my ($self, $name, $temp, $time) = @_;
	my %params = (
		idx   => $self->groupId($name),
		ctemp => $temp || 0,
		time  => $time || 0,
	);
	$self->callApiGet('/services/group/set?'.$self->compileParams(%params));
}

# devices
# =======================================

sub allDevices {
	my ($self) = @_;
	return @{ $self->{devices} } if $self->{devices};
	return @{ $self->{devices} = $self->callApiGet('/services/devices') };
}

sub device {
	my ($self, $name) = @_;
	return (grep { $_->{name} =~ /$name/i } $self->allDevices)[0];
}

sub deviceId {
	my ($self, $name) = @_;
	return $self->device($name)->{deviceId};
}

sub deviceToggle {
	my ($self, $name, $state, $level, $time) = @_;
	my %params = (
		idx   => $self->deviceId($name),
		onoff => $state || 0,
		time  => $time || 0,
	);
	$params{level} = $level if $level;
	$self->callApiGet('/services/device/set?'.$self->compileParams(%params));
}

sub isOn {
	my ($self, $name) = @_;
	my $dev = $self->device($name);
	return unless $dev;
	$self->output("========= Device: $name =========");
	$self->output("on: $dev->{on}");
	return $dev->{on} == 1;
}

sub isOff {
	my ($self, $name) = @_;
	return !$self->isOn($name);
}

# scenes
# =======================================

sub sceneId {
	my ($self, $name) = @_;
	foreach my $g ($self->allGroups) {
		next unless $g;

		my $s = $g->{scenes};
		foreach (keys %$s) {
			return $_ if $s->{$_} =~ /$name/i;
		}
	}
}

sub applyScene {
	my ($self, $name) = @_;
	return $self->callApiGet('/services/scene/recall?sceneId='.$self->sceneId($name));
}

# utils
# ======================================

sub compileParams {
	my ($self, %params) = @_;
	return join '&', map { "$_=$params{$_}" } keys %params;
}

sub runCommand {
	my ($self, $script) = @_;

	$self->output('========= Command =========');
	$self->output($script);
	$script =~ s/eval|`//g;
	$script =~ s/(\w+)\s*\((.*?)\)/$self->parseMethod($1,$2)/ge;
	$self->output($script);
	return unless $script;

	my $result = eval($script);
	$self->output($@) if $@;
	return $result;
}

sub parseMethod {
	my ($self, $name, $attrs) = @_;
	return "$name($attrs)" if $name eq 'if';
	return "\$self->$name(".$self->parseAttributes($attrs).")";
}

sub parseAttributes {
	my ($self, $str) = @_;
	return join ',', map { "'$_'" } split /,/, $str;
}

sub timeBetween {
	my ($self, $from, $to) = @_;

	my ($fh, $fm, $fs) = $from =~ /^(\d+):(\d*):?(\d*)/;
	my $fromSec = $fh * 3600 + $fm * 60 + $fs;

	my ($th, $tm, $ts) = $to =~ /^(\d+):(\d*):?(\d*)/;
	my $toSec = $th * 3600 + $tm * 60 + $ts;

	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
	my $curSec = $hour * 3600 + $min * 60 + $sec;
	my $res;
	if ($fromSec > $toSec) {
		$res = $fromSec <= $curSec || $toSec >= $curSec;
	} else {
		$res = $fromSec <= $curSec && $toSec >= $curSec;
	}

	$self->output('========= Time Between =========');
	$self->output("from:$fromSec, to:$toSec, now:$curSec");
	$self->output("result: $res");

	return $res;
}

sub wait {
	my ($self, $sec) = @_;
	$self->output("========= Wait: $sec =========");
	sleep $sec;
	$self->output('done');
}

1;
