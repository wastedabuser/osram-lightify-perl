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

sub getGroups {
	my ($self) = @_;
	return @{ $self->{groups} } if $self->{groups};
	return @{ $self->{groups} = $self->callApiGet('/services/groups') };
}

sub groupByName {
	my ($self, $name) = @_;
	return (grep { $_->{name} =~ /$name/i } $self->getGroups)[0];
}

sub findGroupId {
	my ($self, $name) = @_;
	return $self->groupByName($args{g})->{groupId};
}

sub toggleGroup {
	my ($self, $name, $state) = @_;
	$state ||= 0;
	$self->callApiGet('/services/group/set?idx='.$self->findGroupId($name).'&onoff='.$state);
}

# devices
# =======================================

sub getDevices {
	my ($self) = @_;
	return @{ $self->{devices} } if $self->{devices};
	return @{ $self->{devices} = $self->callApiGet('/services/devices') };
}

sub deviceByName {
	my ($self, $name) = @_;
	return (grep { $_->{name} =~ /$name/i } $self->getDevices)[0];
}

sub findDeviceId {
	my ($self, $name) = @_;
	return $self->deviceByName($args{d})->{deviceId};
}

sub toggleDevice {
	my ($self, $name, $state) = @_;
	$self->callApiGet('/services/device/set?idx='.$self->findDeviceId($name).'&onoff='.$state);
}

sub isOn {
	my ($self, $name) = @_;
	my $dev = $self->deviceByName($name);
	return unless $dev;
	return $dev->{on} == 1;
}

# scenes
# =======================================

sub findSceneId {
	my ($self, $name) = @_;
	foreach my $g ($self->getGroups) {
		next unless $g;

		my $s = $g->{scenes};
		foreach (keys %$s) {
			return $_ if $s->{$_} =~ /$name/i;
		}
	}
}

sub applySceneByName {
	my ($self, $name) = @_;
	return $self->callApiGet('/services/scene/recall?sceneId='.$self->findSceneId($name));
}

1;
