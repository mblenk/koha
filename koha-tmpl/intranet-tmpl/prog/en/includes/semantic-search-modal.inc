[%#
    The <semantic-search-modal> custom element is hydrated on pages that load
    main-container.inc (which pulls in islands.esm.js). On other pages the
    inner native-HTML fallback is used directly.

    When islands ARE loaded, Vue replaces the inner content with its own render,
    picking up the search-url and llm-available attributes from the element.
    The native fallback (redirect-only) remains the behaviour on non-island pages.
%]
[% USE raw %]
[% USE Koha %]
[% USE BackgroundJob %]
[% IF Koha.Preference('AgentSearchEnabled') %]
    <semantic-search-modal search-url="/cgi-bin/koha/catalogue/search.pl" llm-available="[% BackgroundJob.LLMProviderActive | html %]" borrower-number="[% loggedinusernumber | html %]">
        <div id="semanticSearchModal" class="modal fade" tabindex="-1" aria-labelledby="semanticSearchModalLabel" aria-hidden="true">
            <div class="modal-dialog">
                <div class="modal-content">
                    <div class="modal-header">
                        <h5 id="semanticSearchModalLabel" class="modal-title">Semantic search</h5>
                        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                    </div>
                    <div class="modal-body">
                        <label for="semanticSearchQuery" class="form-label"> Describe what you're looking for in plain language </label>
                        <textarea id="semanticSearchQuery" class="form-control" rows="3" style="margin-top: 1em"></textarea>
                    </div>
                    <div class="modal-footer">
                        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>
                        <button type="button" class="btn btn-primary" id="semanticSearchSubmit">Search</button>
                    </div>
                </div>
            </div>
        </div>
        <script nonce="[% Koha.CSPNonce | $raw %]">
            (function () {
                var modal = document.getElementById("semanticSearchModal");
                if (!modal) return;
                modal.addEventListener("shown.bs.modal", function () {
                    document.getElementById("semanticSearchQuery").focus();
                });
                modal.addEventListener("hidden.bs.modal", function () {
                    document.getElementById("semanticSearchQuery").value = "";
                });
                function doSemanticSearch() {
                    var q = document.getElementById("semanticSearchQuery").value.trim();
                    if (!q) return;
                    window.location.href = "/cgi-bin/koha/catalogue/search.pl?q=" + encodeURIComponent(q) + "&semantic=1";
                }
                document.getElementById("semanticSearchSubmit").addEventListener("click", doSemanticSearch);
                document.getElementById("semanticSearchQuery").addEventListener("keyup", function (e) {
                    if (e.key === "Enter") doSemanticSearch();
                });
            })();
        </script>
    </semantic-search-modal>
[% END %]
