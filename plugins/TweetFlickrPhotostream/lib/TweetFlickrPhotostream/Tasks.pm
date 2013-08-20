package TweetFlickrPhotostream::Tasks;
use strict;

use Encode;
use XML::Simple;
use MT::AtomServer;
use TweetFlickrPhotostream::Util;

sub tweet_flickr_photostream {
    my $plugin = MT->component( 'TweetFlickrPhotostream' );
    my @blogs = MT->model( 'blog' )->load( undef, { no_class => 1, } );
    for my $blog ( @blogs ) {
        my $blog_id = $blog->id;
        my $scope = 'blog:' . $blog_id;
        if ( my $flickr_id = $plugin->get_config_value( 'flickr_id', $scope ) ) {
            if ( my $rss_url = TweetFlickrPhotostream::Util::rss_url( $flickr_id ) ) {
                my $tweet_format = $plugin->get_config_value( 'tweet_format', $scope );
                my $last_updated = $plugin->get_config_value( 'last_updated', $scope );
                my $tweet_limit = $plugin->get_config_value( 'tweet_limit', $scope );
                if ( my $tweets = _get_tweet( $blog_id, $rss_url, $tweet_format, $last_updated, $tweet_limit ) ) {
                    for my $tweet ( @$tweets ) {
                       if ( my $res = TweetFlickrPhotostream::Util::update_twitter( $tweet, $blog_id ) ) {
                            my $log_message = $plugin->translate( 'Update twitter success: [_1]', $res );
                            TweetFlickrPhotostream::Util::success_log( $log_message, $blog_id );
                       }
                    }
                }
            }
        }
    }
}

sub _get_tweet {
    my ( $blog_id, $rss_url, $format, $last_updated, $limit ) = @_;
    return unless $blog_id;
    return unless $rss_url;
    return unless $format;
    my $plugin = MT->component( 'TweetFlickrPhotostream' );
    my $ua = MT->new_ua;
    my $req = HTTP::Request->new( GET => $rss_url ) or return;
    my $res = $ua->request( $req ) or return;
    if ( $res->is_success ) {
        my $content = $res->content;
        my $ref = XMLin( $content, NormaliseSpace => 2 );
        if ( defined $ref->{ xmlns } && $ref->{ xmlns } eq 'http://www.w3.org/2005/Atom' ) {
            my %items = %{ $ref->{ entry } } or return;
            my @items = sort { $items{ $a }->{ updated } cmp $items{ $b }->{ updated } } keys %items;
            my @tweets;
            my $i = 0;
            for my $key ( @items ) {
                my $updated = $items{ $key }->{ updated };
                my $updated_epoch = MT::AtomServer::iso2epoch( undef, $updated );
                if ( $last_updated && ( $updated_epoch < $last_updated ) ) {
                    next;
                }
                if ( my $photo_id = $key ) {
                    $photo_id =~ s!.*/([0-9]{1,})!$1!;
                    if ( my $shorter_url = TweetFlickrPhotostream::Util::shorter_url( $photo_id ) ) {
                        my $tweet = $format;
                        my $title = $items{ $key }->{ title };
                        my $author = $items{ $key }->{ author }->{ name };
                        $tweet = MT::I18N::decode_utf8( $tweet );
                        $title = MT::I18N::decode_utf8( $title );
                        $author = MT::I18N::decode_utf8( $author );
                        my $search_shorter_url = quotemeta( '*shorter_url*' );
                        my $search_title = quotemeta( '*title*' );
                        my $search_author = quotemeta( '*author*' );
                        $tweet =~ s/$search_shorter_url/$shorter_url/g;
                        $tweet =~ s/$search_title/$title/g;
                        $tweet =~ s/$search_author/$author/g;
                        push( @tweets, $tweet );
                    }
                }
                $i++;
                if ( $i eq $limit || $i == scalar( @items ) ) {
                    $last_updated = $updated_epoch;
                    last;
                }
            }
            my $scope = 'blog:' . $blog_id;
            $plugin->set_config_value( 'last_updated', $last_updated, $scope );
            return \@tweets;
        }
    }
    return 0;
}

1;
