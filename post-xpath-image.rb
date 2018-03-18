#!/usr/bin/env ruby
#
require 'em-http-request'
require 'nokogiri'
require 'base64'
require 'yaml'

class PostXpathImage
  def run
    sources_path = ARGV[0]
    posted_image_urls_path = ARGV[1]

    EM.run {
      sources = YAML.load_file(sources_path)
      posted_image_urls = Marshal.load(open(posted_image_urls_path)) rescue []

      puts 'sources_to_candidates'
      sources_to_candidates(sources, posted_image_urls) {|candidates|
        puts 'fetch_images_for_candidates'
        fetch_images_for_candidates(candidates) {|candidates|
          puts 'post_candidates_to_vimage'
          post_candidates_to_vimage(candidates) {|posted_urls|
            posted_image_urls.concat(posted_urls).uniq!
            Marshal.dump(posted_image_urls, open(posted_image_urls_path, 'w')) if posted_image_urls_path

            puts 'done'
            EM.stop
          }
        }
      }
    }
  end

  def sources_to_candidates(sources, posted_image_urls)
    candidates = []
    EM::Iterator.new(sources, 2).each(proc{|source, iter|
      url = source['url']
      http = EM::HttpRequest.new(url).get
      http.callback {
        xml = Nokogiri::XML.parse(http.response)
        if xml
          xml.remove_namespaces!
          xml.xpath(source['xpath']).map{|e| e.text}.each {|extracted|
            candidates << {
              url: extracted,
              tags: source['tags'],
            } unless posted_image_urls.index(extracted)
          }
        else
          puts "Not found: #{url}"
        end
        iter.next
      }
      http.errback {
        p http.error
        iter.next
      }
    }, proc{
      yield candidates
    })
  end

  def fetch_images_for_candidates(candidates)
    EM::Iterator.new(candidates, 2).each(proc{|candidate, iter|
      url = candidate[:url]
      http = EM::HttpRequest.new(url).get
      http.callback {
        image = http.response
        if image
          candidate[:image] = image
        else image
          puts "Not found: #{url}"
        end
        iter.next
      }
      http.errback {
        p http.error
        iter.next
      }
    }, proc{
      candidates.select! {|c| c.has_key?(:image)}
      yield candidates
    })
  end

  def post_candidates_to_vimage(candidates)
    posted_image_urls = []
    EM::Iterator.new(candidates, 2).each(proc{|candidate, iter|
      url = "#{ENV['VIMAGE_ROOT']}images/new"
      http = EM::HttpRequest.new(url).post(
        body: {
          title: 'from post-xpath-image',
          url: candidate[:url],
          tags: candidate[:tags].join(' '),
          base64: Base64::encode64(candidate[:image]),
        },
      )
      http.callback {
        posted_image_urls << candidate[:url]
        iter.next
      }
      http.errback {
        p http.error
        iter.next
      }
    }, proc{
      yield posted_image_urls
    })
  end
end

PostXpathImage.new.run
