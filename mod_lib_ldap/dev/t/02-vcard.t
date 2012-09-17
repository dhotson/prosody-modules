use strict;
use warnings;
use lib 't';

use TestConnection;
use AnyEvent::XMPP::Ext::VCard;
use Test::More;

sub test_vcard {
    my ( $username, $expected_fields ) = @_;

    $expected_fields->{'JABBERID'} = $username . '@' . $TestConnection::HOST;
    $expected_fields->{'VERSION'}  = '2.0';

    my $conn  = TestConnection->new($username);
    my $vcard = AnyEvent::XMPP::Ext::VCard->new;

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    $conn->reg_cb(stream_ready => sub {
        $vcard->hook_on($conn);
    });

    $conn->reg_cb(session_ready => sub {
        $vcard->retrieve($conn, undef, sub {
            my ( $jid, $vcard, $error ) = @_;

            if(eval { $vcard->isa('AnyEvent::XMPP::Error') }) {
                $error = $vcard;
            }

            if($error) {
                $conn->cond->send($error->string);
                return;
            }

            foreach my $key (keys %$vcard) {
                my $value = $vcard->{$key};

                $value = $value->[0];

                if($value eq '') {
                    delete $vcard->{$key};
                } else {
                    $vcard->{$key} = $value;
                }
            }

            is_deeply $expected_fields, $vcard or diag(explain($vcard));
            $conn->cond->send;
        });
    });

    my $error = $conn->cond->recv;

    if($error) {
        fail($error);
        return;
    }
}

plan tests => 5;

test_vcard(one => {
    FN       => 'John Testerson',
    NICKNAME => 'one',
});

test_vcard(two => {
    FN       => 'Jane Testerson',
    NICKNAME => 'two',
});

test_vcard(three => {
    FN       => 'Jerry Testerson',
    NICKNAME => 'three',
});

test_vcard(four => {
    FN       => 'Jack Testerson',
    NICKNAME => 'four',
});

test_vcard(five => {
    FN       => 'Jimmy Testerson',
    NICKNAME => 'five',
});
