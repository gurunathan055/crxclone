require 'appengine-apis/urlfetch'
require 'dm-core'
require 'rexml/document'

class ExtensionNotFoundError < StandardError
end

class Extension
  include DataMapper::Resource
  property :id, Serial
  property :extension_id, String

  has n, :clones, 'ExtensionClone'
  has 1, :cached_extension

  UPDATE_URL = 'http://clients2.google.com/service/update2/crx'
  HTTP_MODULE = AppEngine::URLFetch::HTTP

  def clone_extension
    cached = self.cached_extension
    current_version = nil
    unless cached.nil?
      current_version = cached.version
    end
    self.check_and_update!(current_version)
    self.create_clone
  end

  def check_and_update!(current_version = nil)
    should_update, version, update_url = self.check_most_recent_version(current_version)
    if should_update
      self.update_cache(update_url, version)
    end
    version || current_version
  end

  def update_cache(update_url, version)
    data = HTTP_MODULE.get(URI(update_url))

    cached = self.cached_extension
    if cached.nil?
      cached = CachedExtension.new
      cached.extension = self
      cached.version = version
    end
    cached.packed_data = data
    cached.save

    cached
  end

  def check_most_recent_version(current_version = nil)
    update_uri = URI(UPDATE_URL)
    params = "id=#{self.extension_id}&uc"
    params << "&v=#{current_version}" if current_version
    update_uri.query = "x=#{URI.encode(params, /[^\w.]/)}"

    response = HTTP_MODULE.get(update_uri)
    doc = REXML::Document.new(response)
    elem = doc.elements["gupdate/app[@appid='#{self.extension_id}']/updatecheck"]

    raise ExtensionNotFoundError if elem.nil?

    [
      elem.attributes['status'] != 'noupdate',
      elem.attributes['version'],
      elem.attributes['codebase']
    ]
  end

  def create_clone
    clone = ExtensionClone.new
    clone.extension = self
    clone.created_at = DateTime.now
    clone.last_update_request = DateTime.now
    clone
  end
end