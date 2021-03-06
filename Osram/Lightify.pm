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

sub error {
	my ($self, $str) = @_;
	return $self->{errorSub}->($str) if $self->{errorSub};
	die "**********************************\n$str\n**********************************\n";
}

sub authenticate {
	my ($self) = @_;
	my $result = $self->postRequest(
		'/services/session',
		{   username     => $self->{username},
			password     => $self->{password},
			serialNumber => $self->{serialNumber}
		}
	);
	$self->{token} = $result->{securityToken};
	return $result;
}

sub postRequest {
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
		$self->error($response->status_line.": $url");
	}
}

sub getRequest {
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
		$self->error($response->status_line.": $url");
	}
}

sub checkAuthentication {
	my ($self) = @_;
	return if $self->{token};
	return $self->authenticate();
}

sub callApiPost {
	my ($self, $url, $data) = @_;
	$self->checkAuthentication();
	return $self->postRequest($url, $data);
}

sub callApiGet {
	my ($self, $url, $data) = @_;
	$self->checkAuthentication();
	return $self->getRequest($url, $data);
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
	my $grp = (grep { $_->{name} =~ /$name/i } $self->allGroups)[0];
	$self->error("Can not find group: $name") unless $grp;
	return $grp;
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
	my $dev = (grep { $_->{name} =~ /$name/i } $self->allDevices)[0];
	$self->error("Can not find device: $name") unless $dev;
	return $dev;
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
	$script =~ s/(^|[\s\t])(if)([\s\t\(])/\1<KEYWORD:\2>\3/g;
	$script =~ s/(\w+)\s*\((.*?)\)/$self->parseMethod($1,$2)/ge;
	$script =~ s/(\w+)\s*([^\(\);]*?)\s*(?:(;)|[\n\r]|$)/$self->parseText($1,$2)/ge;
	$script =~ s/<KEYWORD:(\w+)>/\1/g;
	$self->output($script);
	return unless $script;

	my $result = eval($script);
	$self->output($@) if $@;
	return $result;
}

sub call {
	my ($self, $name, @args) = @_;
	return $self->{extend}{$name}->(@args) if $self->{extend} && $self->{extend}{$name};
	return $self->$name(@args);
}

sub parseText {
	my ($self, $name, $attrs) = @_;
	return $self->parseMethod($name, $attrs).';';
}

sub parseMethod {
	my ($self, $name, $attrs) = @_;
	return "$name($attrs)" if $name eq 'if';
	return "\$self->call('$name',".$self->parseAttributes($attrs).")";
}

sub parseAttributes {
	my ($self, $str) = @_;
	return join ',', map { $self->parseAttribute($_) } split /,/, $str;
}

sub parseAttribute {
	my ($self, $str) = @_;
	$str =~ s/^[\s\t]+//;
	$str =~ s/[\s\t]+$//;
	return "'$str'";
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
