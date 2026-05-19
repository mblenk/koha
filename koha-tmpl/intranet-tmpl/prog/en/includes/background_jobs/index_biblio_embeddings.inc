[% USE raw %]
[% SET report  = job.decoded_data.report %]
[% SET decoded = job.decoded_data %]

[% IF decoded.rebuild_all %]
    [% Asset.js("js/job_progress.js") | $raw %]
[% END %]

[% BLOCK report %]
    [% IF decoded.rebuild_all %]
        [% IF job.status == 'finished' %]
            [% IF report %]
                [% IF report.skipped == 0 %]
                    <div class="alert alert-info">Embedding re-index complete. [% report.success | html %] record(s) successfully indexed.</div>
                [% ELSE %]
                    <div class="alert alert-info">Embedding re-index complete. [% report.success | html %] / [% report.total | html %] record(s) indexed. [% report.skipped | html %] record(s) skipped.</div>
                [% END %]
            [% ELSE %]
                <div class="alert alert-info">Job data could not be read, see the logs for details.</div>
            [% END %]
        [% ELSE %]
            [% IF job.status == 'started' %]
                <div class="alert alert-warning">Embedding re-index is in progress. Semantic search is temporarily unavailable.</div>
            [% ELSIF job.status == 'cancelled' %]
                <p>The embedding re-index job was cancelled before it finished.</p>
            [% END %]
            [% INCLUDE "job_progress.inc" job_id=job.id %]
        [% END %]
    [% ELSE %]
        [% IF job.status == 'finished' %]
            [% IF report %]
                [% IF report.success == report.total %]
                    <div class="alert alert-info">[% report.success | html %] bibliographic record(s) successfully indexed with embeddings.</div>
                [% ELSIF report.success == 0 %]
                    <div class="alert alert-info">No records were indexed. All [% report.total | html %] record(s) were skipped.</div>
                [% ELSE %]
                    <div class="alert alert-info">[% report.success | html %] / [% report.total | html %] record(s) indexed with embeddings. [% report.skipped | html %] skipped.</div>
                [% END %]
            [% ELSE %]
                <div class="alert alert-info">Job data could not be read, see the logs for details.</div>
            [% END %]
        [% ELSIF job.status == 'cancelled' %]
            <span>The job has been cancelled before it finished.</span>
        [% END %]
    [% END %]
[% END %]

[% BLOCK detail %]
    [% IF decoded.rebuild_all %]
        [% IF report %]
            <table id="embedding_report_table">
                <thead>
                    <tr>
                        <th>Total records</th>
                        <th>Successfully indexed</th>
                        <th>Skipped</th>
                    </tr>
                </thead>
                <tbody>
                    <tr>
                        <td>[% report.total | html %]</td>
                        <td>[% report.success | html %]</td>
                        <td>[% report.skipped | html %]</td>
                    </tr>
                </tbody>
            </table>
        [% END %]
    [% ELSE %]
        [% IF decoded.record_ids %]
            <h3>Record IDs:</h3>
            <ul>
                [% FOREACH record_id IN decoded.record_ids %]
                    <li><a href="/cgi-bin/koha/catalogue/detail.pl?biblionumber=[% record_id | uri %]">[% record_id | html %]</a></li>
                [% END %]
            </ul>
        [% END %]
    [% END %]
[% END %]

[% BLOCK js %]
    [% IF decoded.rebuild_all %]
        [% INCLUDE 'str/job_progress.inc' job_id=job.id %]
        <script nonce="[% Koha.CSPNonce | $raw %]">
            $(document).ready(function(){
                updateProgress([% job.id | html %], {
                    finish_callback: function(){
                        if(!$('#embedding_report_table').length){
                            window.location.reload();
                        }
                    }
                });
            });
        </script>
    [% END %]
[% END %]
