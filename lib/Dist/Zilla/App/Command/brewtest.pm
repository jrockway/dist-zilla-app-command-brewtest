package Dist::Zilla::App::Command::brewtest;
# ABSTRACT: run your tests against an arbitrary version of perl

use strict;
use warnings;

use App::perlbrew '0.08_01';
use Guard;
use List::Util qw(first);


use Dist::Zilla::App -command;
require Dist::Zilla::App::Command::test;

sub abstract { 'run your tests against an arbitrary version of perl' }

sub opt_spec {
    return (
        [ "perl|p=s", 'select which perlbrew perl to use' ],
        # [ "cpan|c=s", 'select which cpan client to use to install deps' ],
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

sub execute {
    my ($self, $args) = @_;

    # restore perlbrew state when we are done
    my $current_perl = current_perl();

    my $req = $args->perl || die 'need "perl" arg';
    my $new_perl = get_perl($req);
    die "no perls matching $req" unless $new_perl;
    print "Switching to perl '$new_perl'\n";
    print `perlbrew switch \Q$new_perl\E`;


    my $s = scope_guard {
        if($current_perl){
            print `perlbrew switch \Q$current_perl\E`;
        }
        else {
            print `perlbrew off`;
        }
    };

    local $^X = App::perlbrew->get_current_perl(). '/bin/perl';
    local @ARGV = qw(test);
    return $self->app->run;
}

1;
