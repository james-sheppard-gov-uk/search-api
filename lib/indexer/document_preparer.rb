class DocumentPreparer
  def initialize(client)
    @client = client
  end

  def prepared(doc_hash, popularities, options, is_content_index)
    if is_content_index
      doc_hash = prepare_popularity_field(doc_hash, popularities)
      doc_hash = prepare_mainstream_browse_page_field(doc_hash)
      doc_hash = prepare_tag_field(doc_hash)
      doc_hash = prepare_format_field(doc_hash)
      doc_hash = prepare_public_timestamp_field(doc_hash)
    end

    doc_hash = prepare_if_best_bet(doc_hash)
    doc_hash
  end

private

  def prepare_popularity_field(doc_hash, popularities)
    pop = 0.0
    unless popularities.nil?
      link = doc_hash["link"]
      pop = popularities[link]
    end
    doc_hash.merge("popularity" => pop)
  end

  def prepare_mainstream_browse_page_field(doc_hash)
    # Mainstream browse pages were modelled as three separate fields:
    # section, subsection and subsubsection.  This is unhelpful in many ways,
    # so model them instead as a single field containing the full path.
    #
    # In future, we'll get them in this form directly, at which point we'll
    # also be able to there may be multiple browse pages tagged to a piece of
    # content.
    return doc_hash if doc_hash["mainstream_browse_pages"]

    path = [
      doc_hash["section"],
      doc_hash["subsection"],
      doc_hash["subsubsection"]
    ].compact.join("/")

    if path == ""
      doc_hash
    else
      doc_hash.merge("mainstream_browse_pages" => [path])
    end
  end

  def prepare_tag_field(doc_hash)
    tags = []

    tags.concat(Array(doc_hash["organisations"]).map { |org| "organisation:#{org}" })
    tags.concat(Array(doc_hash["specialist_sectors"]).map { |sector| "sector:#{sector}" })

    doc_hash.merge("tags" => tags)
  end

  def prepare_format_field(doc_hash)
    if doc_hash["format"].nil?
      doc_hash.merge("format" => doc_hash["_type"])
    else
      doc_hash
    end
  end

  def prepare_public_timestamp_field(doc_hash)
    if doc_hash["public_timestamp"].nil? && !doc_hash["last_update"].nil?
      doc_hash.merge("public_timestamp" => doc_hash["last_update"])
    else
      doc_hash
    end
  end

  # If a document is a best bet, and is using the stemmed_query field, we
  # need to populate the stemmed_query_as_term field with a processed version
  # of the field.  This produces a representation of the best-bet query with
  # all words stemmed and lowercased, and joined with a single space.
  #
  # At search time, all best bets with at least one word in common with the
  # user's query are fetched, and the stemmed_query_as_term field of each is
  # checked to see if it is a substring match for the (similarly normalised)
  # user's query.  If so, the best bet is used.
  def prepare_if_best_bet(doc_hash)
    if doc_hash["_type"] != "best_bet"
      return doc_hash
    end

    stemmed_query = doc_hash["stemmed_query"]
    if stemmed_query.nil?
      return doc_hash
    end

    doc_hash["stemmed_query_as_term"] = " #{analyzed_best_bet_query(stemmed_query)} "
    doc_hash
  end

  # duplicated in index.rb
  def analyzed_best_bet_query(query)
    analyzed_query = JSON.parse(@client.get_with_payload(
      "_analyze?analyzer=best_bet_stemmed_match", query))

    analyzed_query["tokens"].map { |token_info|
      token_info["token"]
    }.join(" ")
  end
end
