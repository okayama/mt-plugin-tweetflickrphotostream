package TweetFlickrPhotostream::Tags;
use strict;

sub _hdlr_flickr_shorter_url {
    my ( $ctx, $args, $cond ) = @_;
    if ( my $photo_id = $args->{ photo_id } ) {
        if ( $photo_id =~ /^[0-9]{1,}$/ ) {
            return get_shorter_url( $photo_id ) || '';
        }
    }
    return '';
}

1;
