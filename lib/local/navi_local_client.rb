require Gem::Specification.find_by_name("navi_client").gem_dir+"/lib/client"
module NaviClient
  class Local
    include Client
    def initialize(sso_web_url = 'http://localhost:3008')
     # flag to print Ruby library debug info (very detailed)
     @net_imap_debug = false

     # flag to mark email as read after gets downloaded.
     @mark_as_read = false

     # flag to turn on/off debug mode.
     @debug = false

     # override the log file
     mkdir_if_not_exist(config['client_log_file'])
     @logger = Logger.new(config['client_log_file'])

     @sso_web_url = sso_web_url
     # naviai command
     @cmd = 'naviai'
     # authentication token received from sso_web used to authenticate the request to database_api
     @token = nil
   end

    def download(message, custom_uid)
      download_path = config['download_path']
      if ['text/plain', 'text/html'].include? message.mime_type

        h = Hash.new
        out_file = download_path + message.mime_type + "/"+custom_uid
        mkdir_if_not_exist(out_file)

        File.open(out_file, 'w') { |file| file.write(encrypt(message.decoded)) }
        key = message.mime_type.split("/").join("_")

        h[key] = out_file
        return h
      end
    end
  end
end
