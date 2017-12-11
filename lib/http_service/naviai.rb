require "httparty"

GO_SERVER_URL = 'http://localhost:9090/v2/metas'

module HTTPService
  class NaviAI

    def self.start(file_path, client_type, token)
      if client_type == 'local'
        go_url = 'http://localhost:9090'
      else
        go_url = ''
      end
      HTTParty.post(GO_SERVER_URL, body: { client_type: client_type, list_meta_path: file_path, token: token }.to_json)
    end
  end
end
