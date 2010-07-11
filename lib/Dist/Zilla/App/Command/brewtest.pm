package Dist::Zilla::App::Command::brewtest;
# ABSTRACT: run your tests against an arbitrary version of perl

use strict;
use warnings;

use Dist::Zilla::App -command;
require Dist::Zilla::App::Command::test;
require Dist::Zilla::App::Command::listdeps;
use Dist::Zilla::Dist::Builder;

use App::perlbrew '0.08_01';
use Guard;
use List::Util qw(first);
use File::Which qw(which);

sub abstract { 'run your tests against an arbitrary version of perl' }

sub opt_spec {
    return (
        [ 'perl|p=s', 'select which perlbrew perl to use' ],
        [ 'installdeps|i!', "install the dist's deps under the new perl" ],
        # [ 'cpan|c=s', 'select which cpan client to use to install deps' ],
    );
}

sub current_perl {
    my $perl = first { $_->{is_current } } App::perlbrew->calc_installed;
    return if !$perl;
    return $perl->{name};
}

sub get_perl {
    my $perl = shift;
    my @perls = map { $_->{name} } App::perlbrew->calc_installed;
    my $exact = first { $_ eq $perl } @perls;
    return $exact if $exact;
    return first { /\Q$perl/i } @perls;
}

sub find_perlbrew {
    my $perlbrew = which('perlbrew') or die 'no perlbrew?';
    chomp $perlbrew;
    return "$^X $perlbrew";
}

sub get_prereqs {
    my $self = shift;

    # we create a fresh dzil, since calculating the deps confuses dzil
    # to the point of being unable to run tests.  yeah.
    my $z = Dist::Zilla::Dist::Builder->from_config({
        chrome => $self->app->chrome,
        _global_stashes => $self->app->_build_global_stashes,
    });

    # this clever hack comes from the listdeps command
    my $l = $z->chrome->logger;
    $z->chrome->_set_logger(
        Log::Dispatchouli->new({ ident => 'Dist::Zilla' }),
    );

    my $log_guard = scope_guard { $z->chrome->_set_logger($l) };

    return Dist::Zilla::App::Command::listdeps->extract_dependencies($z);
}

sub execute {
    my ($self, $args) = @_;

    my $logger = $self->app->chrome->logger->proxy({ proxy_prefix => '[brew] ' });

    # restore perlbrew state when we are done
    my $perlbrew = find_perlbrew();
    my $current_perl = current_perl();

    my $req = $args->perl || die 'need "perl" arg';
    my $new_perl = get_perl($req);
    $logger->log_fatal("no perls matching $req") unless $new_perl;

    # switch to the new perl, and install a guard to go back to the old one
    $logger->log("Switching to perl '$new_perl'");
    print `$perlbrew switch \Q$new_perl\E`;
    my $s = scope_guard {
        if($current_perl){
            $logger->log("Switching back to perl '$current_perl'.");
            print `$perlbrew switch \Q$current_perl\E`;
        }
        else {
            $logger->log("Disabling perlbrew.");
            print `$perlbrew off`;
        }
    };

    # install deps under the new perl, if we want to

    if($args->{installdeps}){
        $logger->log("Determining deps for the dist...");
        my @prereqs = $self->get_prereqs;
        $logger->log('Installing '. join ',', @prereqs);
        system('cpan', @prereqs);
    }

    local $^X = App::perlbrew->get_current_perl(). '/bin/perl';
    local @ARGV = qw(test);
    return $self->app->run;
}

1;
