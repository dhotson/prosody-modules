use strict;
use warnings;
use lib 't';

use TestConnection;
use Test::More;

my @users = (
    'one',
    'two',
    'three',
    'four',
    'five',
);

plan tests => scalar(@users) + 2;

foreach my $username (@users) {
    my $conn = TestConnection->new($username);

    $conn->reg_cb(session_ready => sub {
        $conn->cond->send;
    });

    my $error = $conn->cond->recv;
    ok(! $error) or diag($error);
}

do {
    my $conn = TestConnection->new('one', password => '23451');

    $conn->reg_cb(session_ready => sub {
        $conn->cond->send;
    });

    my $error = $conn->cond->recv;
    ok($error);
};

do {
    my $conn = TestConnection->new('six', password => '12345');

    $conn->reg_cb(session_ready => sub {
        $conn->cond->send;
    });

    my $error = $conn->cond->recv;
    ok($error);
};
