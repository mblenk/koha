export class LLMProvidersAPIClient {
    constructor(HttpClient) {
        this.httpClient = new HttpClient({
            baseURL: "/api/v1/llm_providers",
        });
    }

    get llm_providers() {
        return {
            create: llm_provider =>
                this.httpClient.post({
                    endpoint: "",
                    body: llm_provider,
                }),
            delete: id =>
                this.httpClient.delete({
                    endpoint: "/" + id,
                }),
            update: (llm_provider, id) =>
                this.httpClient.put({
                    endpoint: "/" + id,
                    body: llm_provider,
                }),
            get: id =>
                this.httpClient.get({
                    endpoint: "/" + id,
                }),
            getAll: (query, params) =>
                this.httpClient.getAll({
                    endpoint: "/",
                    query,
                    params,
                    headers: {},
                }),
            count: (query = {}) =>
                this.httpClient.count({
                    endpoint:
                        "?" +
                        new URLSearchParams({
                            _page: 1,
                            _per_page: 1,
                            ...(query && { q: JSON.stringify(query) }),
                        }),
                }),
        };
    }
}

export default LLMProvidersAPIClient;
