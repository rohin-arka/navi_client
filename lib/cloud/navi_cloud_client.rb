require Gem::Specification.find_by_name("navi_client").gem_dir+"/lib/client"

module NaviClient
  class Cloud
    include Client
    def initialize(sso_web_url = "http://localhost:3008/", current_user)
      # flag to print Ruby library debug info (very detailed)
      @net_imap_debug = false

      # flag to mark email as read after gets downloaded.
      @mark_as_read = false

      # flag to turn on/off debug mode.
      @debug = false

      @logger = nil

      # sso_web (authentication) config.
      @sso_web_url = sso_web_url
      # authentication token received from sso_web used to authenticate the request to database_api
      @token = nil
      @current_user = current_user

      # client_type
      @client_type = "cloud"
    end

    def override_logger(logger)
      @logger = logger
    end

    #
    # login
    #
    # login to the navi-cloud and get the authentication token
    #
    def login(session_token)
      @token = session_token
    end

    def send_request(in_filenames = [])
      unless in_filenames.blank?
        download_path = config['s3_download_folder']
        filepath = download_path + "/inputs/" + (Time.now.to_f * 1000).to_s
        filename = upload_to_s3(filepath, in_filenames.join("\n"))

        HTTPService::NaviAI.start(filename, @client_type, @token, @current_user)
      end
    end

    def download(message, custom_uid)
      download_path = config[:s3_download_folder]
      if ['text/plain', 'text/html'].include? message.mime_type

        h = Hash.new
        out_file = download_path + "/" + message.mime_type + "/"+custom_uid

        s3_filepath = upload_to_s3(out_file, encrypt(message.decoded))
        key = message.mime_type.split("/").join("_")

        h[key] = s3_filepath
        return h
      end
    end

    def save(data={}, filename)
      download_path = config[:s3_download_folder]
      filepath = download_path + "/" + filename + ".yml"

      return upload_to_s3(filepath, data.to_yaml)
    end

    def upload_to_s3(file_path, content)
      credentials = Aws::Credentials.new(config[:aws_key], config[:aws_secret])
      s3 = Aws::S3::Client.new(credentials: credentials, region: config[:aws_region])
      obj = s3.put_object({
                            body: content,
                            bucket: config[:s3_bucket],
                            key: file_path
                          })
      return file_path if obj.successful?
      return ""
    end

    def config
      YAML.load_file(Rails.root.join("config/navi_client.yml")).with_indifferent_access
    end
  end
end
