require "httparty"

GO_SERVER_URL = 'http://localhost:9090'

CLIENT_TYPE = 'locallockbox'

module HTTPService
  class NaviAI

    def self.start(start_time, end_time)
      HTTParty.post(GO_SERVER_URL, body: {
                                          client_type: CLIENT_TYPE,
                                          start_time: start_time,
                                          end_time: end_time
                                           })
    end
  end
end
