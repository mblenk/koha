package Koha::SearchEngine::LLMClient;

# Copyright 2026 Openfifth
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <https://www.gnu.org/licenses>.

=head1 NAME

Koha::SearchEngine::LLMClient - provider-agnostic chat completion client

=head1 SYNOPSIS

    my $client = Koha::SearchEngine::LLMClient->new;
    my $reply  = $client->chat([
        { role => 'user', content => 'What books do you have about climate?' }
    ]);

=head1 DESCRIPTION

Sends a conversation to an LLM chat completion API and returns the reply
string. All configuration — endpoint URL, model, auth, request/response
format, and system prompt — is read from the active row in the
C<llm_providers> table.

Template sentinels in C<request_body_template>:

=over 4

=item C<{{model}}> — substituted with the provider's model name

=item C<{{messages}}> — substituted with the full messages array (as a JSON array)

=item C<{{system_prompt}}> — substituted with the provider's system prompt text

=back

Returns C<undef> silently on any failure so callers can degrade gracefully.

=cut

use Modern::Perl;

use parent qw(Koha::SearchEngine::ProviderClient);

use Try::Tiny qw( catch try );
use LWP::UserAgent;
use HTTP::Request;
use JSON qw( decode_json encode_json );
use Koha::LLMProviders;

use constant LWP_TIMEOUT => 120;

=head1 METHODS

=head2 new

    my $client = Koha::SearchEngine::LLMClient->new( %args );

Constructor. In production, reads all configuration from the active
C<llm_providers> row. For tests, all fields may be supplied directly
as named arguments (presence of C<url> triggers the test bypass path):

    url                   — chat completions endpoint
    model                 — model name
    api_key               — bearer token (optional)
    auth_type             — 'none' or 'bearer' (default: 'none')
    request_body_template — JSON template with {{model}}, {{messages}}, {{system_prompt}}, {{tool_definitions}}
    response_key          — dot-notation path to reply text in the response
    system_prompt         — system prompt text (optional)
    tool_definitions      — parsed arrayref of tool definitions (optional)

Dies if no active provider is configured and no args are supplied.

=cut

sub new {
    my ( $class, $args ) = @_;
    $args //= {};

    my (
        $url, $model, $api_key, $auth_type, $request_body_template, $response_key, $system_prompt,
        $tool_definitions
    );

    if ( $args->{url} ) {
        $url                   = $args->{url};
        $model                 = $args->{model}                 // die "model required";
        $api_key               = $args->{api_key}               // '';
        $auth_type             = $args->{auth_type}             // 'none';
        $request_body_template = $args->{request_body_template} // die "request_body_template required";
        $response_key          = $args->{response_key}          // 'choices.0.message.content';
        $system_prompt         = $args->{system_prompt}         // '';
        $tool_definitions      = $args->{tool_definitions};
    } else {
        my $record = Koha::LLMProviders->search( { status => 'active' } )->next;
        die "Koha::SearchEngine::LLMClient: No active LLM provider configured"
            unless $record;
        $url   = $record->url;
        $model = $record->model;
        die "Koha::SearchEngine::LLMClient: active provider has no URL configured"
            unless $url;
        die "Koha::SearchEngine::LLMClient: active provider has no model configured"
            unless $model;
        $api_key               = $record->plain_text_api_key // '';
        $auth_type             = $record->auth_type;
        $request_body_template = $record->request_body_template;
        $response_key          = $record->response_key;
        $system_prompt         = $record->system_prompt // '';
        $tool_definitions =
            $record->tool_definitions
            ? decode_json( $record->tool_definitions )
            : undef;
    }

    return bless {
        _url                   => $url,
        _model                 => $model,
        _api_key               => $api_key,
        _auth_type             => $auth_type,
        _request_body_template => $request_body_template,
        _response_key          => $response_key,
        _system_prompt         => $system_prompt,
        _tool_definitions      => $tool_definitions,
        _ua                    => LWP::UserAgent->new( timeout => LWP_TIMEOUT ),
    }, $class;
}

=head2 chat

    my $reply = $client->chat( \@messages, $system_prompt );

Sends C<\@messages> (an arrayref of C<{ role =E<gt> ..., content =E<gt> ... }> hashrefs,
I<without> a system-role entry) to the LLM provider and returns the reply string,
or C<undef> on failure.

C<$system_prompt> is optional; it defaults to the provider's configured system prompt.
How it is injected depends on the C<request_body_template>:

=over 4

=item * If the template contains C<{{system_prompt}}> (e.g. Anthropic), the prompt is
substituted there and the messages array is sent as-is.

=item * Otherwise (e.g. OpenAI, Ollama), a C<{ role =E<gt> 'system' }> entry is prepended
to the messages array before substitution.

=back

=cut

sub chat {
    my ( $self, $messages, $system_prompt ) = @_;
    $system_prompt //= $self->{_system_prompt} // '';

    return try {
        my $reply = $self->_do_chat( $messages, $system_prompt );
        return $reply;
    } catch {
        warn "Koha::SearchEngine::LLMClient: chat failed: $_\n";
        return undef;
    };
}

=head2 system_prompt

    my $prompt = $client->system_prompt;

Returns the configured system prompt string.

=cut

sub system_prompt { return $_[0]->{_system_prompt} }

=head2 chat_with_tools

    my $result = $client->chat_with_tools( \@messages, $system_prompt, \@tools );

Like C<chat()> but includes tool definitions in the request. Returns a hashref:

    { type => 'tool_call', tool_calls => [...], raw_message => {...} }
    { type => 'text',      reply => '...' }

or C<undef> on failure. C<\@tools> is optional — omit it to suppress tool
definitions while preserving the structured return type.

=cut

sub chat_with_tools {
    my ( $self, $messages, $system_prompt, $tools ) = @_;
    $system_prompt //= $self->{_system_prompt} // '';

    return try {
        $self->_handle_chat_with_tools( $messages, $system_prompt, $tools );
    } catch {
        warn "chat_with_tools failed: $_\n";
        return undef;
    };
}

=head2 _handle_chat_with_tools

    my $result = $self->_handle_chat_with_tools( \@messages, $system_prompt, \@tools );

Builds and sends the request, then checks the response for tool calls before
falling back to plain text extraction. Dies on HTTP error or if neither tool
calls nor reply text are found.

=cut

sub _handle_chat_with_tools {
    my ( $self, $messages, $system_prompt, $tools ) = @_;

    my $body     = $self->_build_request_body_with_tools( $messages, $system_prompt, $tools );
    my $response = $self->_make_request($body);

    my $data   = decode_json( $response->decoded_content );
    my $result = $self->_extract_tool_calls($data);
    return $result if $result;

    my $reply = $self->_resolve_path( $data, $self->{_response_key} );
    die "No reply text or tool calls in response from '$self->{_url}'"
        unless defined $reply && length $reply;

    return { type => 'text', reply => $reply };
}

=head2 _build_request_body_with_tools

    my $json = $self->_build_request_body_with_tools( \@messages, $system_prompt, \@tools );

Like C<_build_request_body> but also resolves the C<{{tool_definitions}}> sentinel.
C<\@tools> overrides the provider's stored C<tool_definitions>; pass C<undef> to use
the stored definitions. When the template has no C<{{tool_definitions}}> sentinel,
falls back to injecting the tools array as a top-level C<tools> key.

=cut

sub _build_request_body_with_tools {
    my ( $self, $messages, $system_prompt, $tools ) = @_;
    $system_prompt //= $self->{_system_prompt} // '';

    my $structure = decode_json( $self->{_request_body_template} );

    my $has_system_sentinel = index( $self->{_request_body_template}, '{{system_prompt}}' ) >= 0;
    my $chat_messages =
          $has_system_sentinel
        ? $messages
        : [ { role => 'system', content => $system_prompt }, @$messages ];

    my $tool_defs = $tools // $self->{_tool_definitions};
    my %subs      = (
        '{{model}}'         => $self->{_model},
        '{{messages}}'      => $chat_messages,
        '{{system_prompt}}' => $system_prompt,
    );
    $subs{'{{tool_definitions}}'} = $tool_defs if defined $tool_defs;
    $self->_substitute_sentinels( $structure, \%subs );

    # Fallback for templates without {{tool_definitions}} sentinel
    my $has_tools_sentinel = index( $self->{_request_body_template}, '{{tool_definitions}}' ) >= 0;
    $structure->{tools} = $tool_defs
        if !$has_tools_sentinel && $tool_defs && @$tool_defs;
    return encode_json($structure);
}

=head2 _extract_tool_calls

    my $result = $self->_extract_tool_calls($data);

Returns a hashref:

    { type => 'tool_call', tool_calls => [...], raw_message => {...} }

where each entry in C<tool_calls> is C<{ name => '...', arguments => \%hashref }>.
Returns C<undef> if no tool calls are present in the response.

=cut

sub _extract_tool_calls {

    #FIXME: Needs to be more provider agnostic
    my ( $self, $data ) = @_;

    my ( $raw_tool_calls, $raw_message );

    if ( ref $data->{message} eq 'HASH' && ref $data->{message}->{tool_calls} eq 'ARRAY' ) {
        $raw_tool_calls = $data->{message}->{tool_calls};
        $raw_message    = $data->{message};
    } elsif ( ref $data->{choices} eq 'ARRAY'
        && ref $data->{choices}->[0]->{message} eq 'HASH'
        && ref $data->{choices}->[0]->{message}->{tool_calls} eq 'ARRAY' )
    {
        $raw_tool_calls = $data->{choices}->[0]->{message}->{tool_calls};
        $raw_message    = $data->{choices}->[0]->{message};
    }

    return undef unless $raw_tool_calls && @$raw_tool_calls;

    my @tool_calls;
    for my $tool_call (@$raw_tool_calls) {
        my $fn   = $tool_call->{function} or next;
        my $name = $fn->{name}            or next;
        my $args = $fn->{arguments};

        # Some providers send arguments as a JSON string, others send a hashref
        $args = decode_json($args) if defined $args && !ref $args;

        push @tool_calls, { name => $name, arguments => $args // {} };
    }

    return undef unless @tool_calls;
    return { type => 'tool_call', tool_calls => \@tool_calls, raw_message => $raw_message };
}

=head2 _do_chat

    my $reply = $self->_do_chat(\@messages);

Orchestrates the full chat request: builds the request body, sends the HTTP
request, decodes the JSON response, and extracts the reply text using the
configured C<response_key> path. Dies on HTTP error or if no reply text is
found in the response.

=cut

sub _do_chat {
    my ( $self, $messages, $system_prompt ) = @_;

    my $body     = $self->_build_request_body( $messages, $system_prompt );
    my $response = $self->_make_request($body);

    my $data  = decode_json( $response->decoded_content );
    my $reply = $self->_resolve_path( $data, $self->{_response_key} );
    die "No reply text in response from '$self->{_url}'"
        unless defined $reply && length $reply;

    return $reply;
}

=head2 _build_request_body

    my $json = $self->_build_request_body(\@messages, $system_prompt);

Decodes C<request_body_template> as JSON and substitutes the C<{{model}}>,
C<{{messages}}>, and C<{{system_prompt}}> sentinels. Returns the resulting
structure re-encoded as a JSON string.

If the template contains C<{{system_prompt}}> (e.g. Anthropic), C<$system_prompt>
is substituted there and C<{{messages}}> receives the conversation messages as-is.
Otherwise, a C<{ role =E<gt> 'system' }> entry is prepended to C<{{messages}}> so
providers that carry the system prompt inside the messages array (e.g. OpenAI,
Ollama) receive it correctly.

=cut

sub _build_request_body {
    my ( $self, $messages, $system_prompt ) = @_;
    $system_prompt //= $self->{_system_prompt} // '';

    my $structure = decode_json( $self->{_request_body_template} );

    my $has_system_sentinel = index( $self->{_request_body_template}, '{{system_prompt}}' ) >= 0;

    my $chat_messages =
          $has_system_sentinel
        ? $messages
        : [ { role => 'system', content => $system_prompt }, @$messages ];

    my %subs = (
        '{{model}}'         => $self->{_model},
        '{{messages}}'      => $chat_messages,
        '{{system_prompt}}' => $system_prompt,
    );
    $self->_substitute_sentinels( $structure, \%subs );
    return encode_json($structure);
}

1;
