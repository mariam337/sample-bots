require "lead_generator/court/scraper"
require "lead_generator/utility"
require "date"

class LeadGenerator::Court::CaliforniaVentura::Scraper < LeadGenerator::Court::Scraper
  SCRAPER_ID = "court:judicial_california"
  JURISDICTION = "Ventura County - California"
  COURT = "Ventura County - California"

  def initialize(options = {})
    options[:scraper_id] = SCRAPER_ID
    options[:jurisdiction] = JURISDICTION
    options[:court] = COURT
    options[:day_range] = 7
    super(options)
  end

  private

  ##
  # Mines all court cases for a given date range. In this particular
  # instance, we must iterate over two different civil courts since
  # multi select is not available.
  def complaints_within_range(start_date, end_date)
    logger.log "*****************"
    logger.log "Fetch cases for #{start_date}-#{end_date}"
    logger.log "*****************"

    begin
      tries ||= 3
      go_to_search_page
      # Click on Agree button
      Watir::Wait.until(timeout: 30) { browser.element(id: "SearchFromDate").exists? }
      pp = Nokogiri::HTML(browser.html)
      
      browser.text_field(id: "SearchFromDate").set(start_date)
      browser.text_field(id: "SearchToDate").set(end_date)
      browser.button(id: "btnSubmit")
      browser.button(id: "btnSubmit").click
      sleep(10)

      return if !browser.table(id: "searchresults").exists?

      all_links = []
      iterator = 1
      pp = Nokogiri::HTML(browser.html)
      while true
        puts "Page Number ---> #{iterator}"
        all_links << pp.css("#searchresults").css("tr").map{|e| "http://www.ventura.courts.ca.gov"+e.css("a")[0]['href'] rescue nil}.reject(&:nil?)
        break if pp.css("a.paginate_button.next.disabled").count != 0
        browser.link(text: "Next").click
        sleep(3)
        pp = Nokogiri::HTML(browser.html)
        iterator += 1
      end

      all_links = all_links.flatten.uniq
      puts "Total Records to be Processed ---> #{all_links.count}"
      process_results(all_links)

    rescue Watir::Wait::TimeoutError => e
      logger.log "Timeout; back off and try again.."
      LeadGenerator::Utility.random_wait
      tries -= 1
      retry unless tries.zero? ## retries up to 3 times on timeout
    end
  end

  ##
  # Processes all the search results returned in the table. The output
  # varies widely and so this function will change significantly. Mined data
  # is printed to the console as a proof of concept.
  
  def get_values(page, search_text)
    values = page.css("td").select{|e| e.text.include? search_text}
    if !values.empty?
      value = values[-1].next_element.text.strip
    else
      value = "NULL"
    end
    value
  end

  def process_results(all_records)
    LeadGenerator::Utility.random_wait

    logger.log "Processing results"

    data_array = []
    all_records.each_with_index do |record, index|
      
      browser.goto record
      sleep(5)
      page = Nokogiri::HTML(browser.html)
      
      case_number = get_values(page, "Case Number")
      case_title = get_values(page, "Case Title")
      case_category = get_values(page, "Case Category")
      date_filed = DateTime.strptime(get_values(page, "Filed Date"), "%m/%d/%Y").to_date
      case_type = get_values(page, "Case Type")
      case_status = get_values(page, "Case Status")
      location = get_values(page, "Location")
      
      parties = fetch_parties_and_attorneys(page)
      last_activity_date = fetch_activities(page)
      
      puts 
      puts "------------------------------------------------------------------------"
      puts "Processing Link --->  #{record}"
      puts 
      
      data = {
        case_id: case_number,
        docket_number: case_number,
        plaintiff: parties[:plaintiffs],
        defendant: parties[:defendants],
        source: SCRAPER_ID,
        case_type: case_type,
        court_type: "state",
        court: COURT,
        status: case_status,
        case_category: case_category,
        location: location,
        parties: case_title,
        date_filed: date_filed,
        date_updated: last_activity_date,
        mined_date: Date.today.to_s,
        exclusion: false,
        link: record,
        plaintiff_law_firm: parties[:plaintiff_attorneys],
        defendant_law_firm: parties[:defendant_attorneys],
        implicit_status: case_status,
        free_download: false,
        scraper_id: SCRAPER_ID
      }
      pp data

      puts 
      puts "------------------------------------------------------------------------"
      
      browser.back
      sleep(15)
    end
  end

  def get_data(all_rows, search_text)
    party, attorney = ""
    values = all_rows.select{|e| e.text.include? search_text}
    if !values.empty?
      party = values[0].css("td")[0].text rescue nil
      attorney = values[0].css("td")[-2].text rescue nil
    else
      party, attorney = ""
    end
    [party, attorney]
  end

  def fetch_parties_and_attorneys(page)
    defendants = []
    defendant_attorneys = []
    plaintiffs = []
    plaintiff_attorneys = []
    all_rows = page.css("#participantstable").css("tr")[1..-1]
    
    retrieved_defendants, retrieved_defendant_attorneys = get_data(all_rows, "Respondent")
    defendants << retrieved_defendants
    defendant_attorneys << retrieved_defendant_attorneys

    retrieved_defendants, retrieved_defendant_attorneys = get_data(all_rows, "Appellee")
    defendants << retrieved_defendants
    defendant_attorneys << retrieved_defendant_attorneys
    retrieved_defendants, retrieved_defendant_attorneys = get_data(all_rows, "Defendant")
    defendants << retrieved_defendants
    defendant_attorneys << retrieved_defendant_attorneys

    retrieved_plaintiffs, retrieved_plaintiff_attorneys = get_data(all_rows, "Petitioner")
    plaintiffs << retrieved_plaintiffs
    plaintiff_attorneys << retrieved_plaintiff_attorneys
    retrieved_plaintiffs, retrieved_plaintiff_attorneys = get_data(all_rows, "Appellant")
    plaintiffs << retrieved_plaintiffs
    plaintiff_attorneys << retrieved_plaintiff_attorneys
    retrieved_plaintiffs, retrieved_plaintiff_attorneys = get_data(all_rows, "Plaintiff")    
    plaintiffs << retrieved_plaintiffs
    plaintiff_attorneys << retrieved_plaintiff_attorneys
    
    data_hash = {}
    
    data_hash[:plaintiffs] = plaintiffs.flatten.reject(&:nil?).reject(&:empty?).join(", ")
    data_hash[:defendants] = defendants.flatten.reject(&:nil?).reject(&:empty?).join(", ")
    data_hash[:plaintiff_attorneys] = plaintiff_attorneys.flatten.reject(&:nil?).reject(&:empty?).uniq.join(", ")
    data_hash[:defendant_attorneys] = defendant_attorneys.flatten.reject(&:nil?).reject(&:empty?).uniq.join(", ")
    
    data_hash
  end

  ##
  # Determines last activity date based on docket informaton. Last activity date is
  # the date of the last entry in the docket activity table.
  def fetch_activities(page)
    get_date = page.css("#roatbl").css("tr").select{|e| e.text.include? "#{start_date.split("-")[0]}"}[0] rescue "NULL"
    date = DateTime.strptime(get_date.css("td")[1].text, "%m/%d/%Y").to_date rescue "NULL"
  end

  def go_to_search_page
    browser.goto LeadGenerator::Court::CaliforniaVentura::Config::SEARCH_PAGE
  end
end
