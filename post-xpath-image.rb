#!/usr/bin/env ruby
#
require 'em-http-request'
require 'nokogiri'
require 'base64'

class PostXpathImage
  SOURCES = [
    {
      url: 'https://queryfeed.net/twitter?q=%E6%9F%B4%E7%8A%AC++filter%3Aimages&title-type=user-name-both&geocode=',
      xpath: '//item/enclosure/@url',
      tags: ['post-xpath-image', '柴犬'],
    },
  ]

  def run
    EM.run {
      puts 'sources_to_candidates'
      sources_to_candidates(SOURCES) {|candidates|
        puts 'fetch_images_for_candidates'
        fetch_images_for_candidates(candidates) {|candidates|
          puts 'post_candidates_to_vimage'
          post_candidates_to_vimage(candidates) {
            puts 'done'
            EM.stop
          }
        }
      }
    }
  end

  def sources_to_candidates(sources)
    candidates = []
    EM::Iterator.new(SOURCES, 2).each(proc{|source, iter|
      url = source[:url]
      http = EM::HttpRequest.new(url).get
      http.callback {
        xml = Nokogiri::XML.parse(http.response)
        if xml
          xml.remove_namespaces!
          xml.xpath(source[:xpath]).map{|e| e.text}.each {|extracted|
            candidates << {
              url: extracted,
              tags: source[:tags],
            }
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
    EM::Iterator.new(candidates, 8).each(proc{|candidate, iter|
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
        iter.next
      }
      http.errback {
        p http.error
        iter.next
      }
    }, proc{
      yield
    })
  end
end

PostXpathImage.new.run
