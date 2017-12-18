require "httparty"

module HTTPService
  class NaviAI

    def self.start(file_path, client_type, token)
      go_url = 'http://localhost:9090/v2/metas'
      if client_type == 'cloud'
        go_url = 'http://34.214.134.104:9090/v2/metas'
      end
      HTTParty.post(go_url, body: { client_type: client_type, list_meta_path: file_path, token: token }.to_json)
    end
  end
end
