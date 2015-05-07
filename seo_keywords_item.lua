local http = require "socket.http"
local cjson = require "cjson"
local iconv = require "iconv"

fake_header = function (is_mobile)
    local headers = {}
    if is_mobile == "1" then
        headers["User-Agent"] = "Mozilla/5.0 (iPhone; U; CPU iPhone OS 3_0 like Mac OS X; en-us) AppleWebKit/528.18 (KHTML, like Gecko) Version/4.0 Mobile/7A341 Safari/528.16"
    else
        headers["User-Agent"] = "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:32.0) Gecko/20100101 Firefox/32.0"
    end
    return headers
end

patterns = function (is_mobile)
    local tbody_pattern
    local item_pattern
    local link_pattern
    local copy_txt_pattern
    local review_num_pattern
    local price_pattern
    local point_pattern
    local sales_desc_pattern = "<span%s+class=\"sale_desc\">(.-)</span>"
    local item_desc_pattern = "<span%s+class=\"item_desc\">(.-)</span>"
    
    if is_mobile == "1" then
        tbody_pattern = "<div%s+data%-ratUnit=\"true\"%s+class=\"resultItem%s+displayedItem\">.*<script%s+id=\"spmallAsuraku_viewTemplate\""
        item_pattern = "<div%s+data%-ratUnit=\"true\"%s+class=\"resultItem%s+displayedItem\">.-<li%s+class=\"itemPrice\">.-</div>"
        link_pattern = "<dt%s+class=\"itemName\">.-<a%s+href=\"http://item.rakuten.co.jp/([^/]-)/([^/]-)/\"%s+target=\"_top\">(.-)</a>"
        copy_txt_pattern = "<dd%s+class=\"itemTxt\">(.-)</dd>"
        review_num_pattern = "<li%s+class=\"itemIcnRvw\">.-<a%s+href=\"http://review.rakuten.co.jp/.-\">(%d+)件"
        price_pattern = "<li%s+class=\"itemPrice\">.-([,0-9]+)円</li>"
        point_pattern = "<li%s+class=\"itemPoint\">.-(%d+)倍</li>"
        
    else
        tbody_pattern = "<div%s+class=\"searchAccuracyMeasurement\".*<div%s+id=\"rsrPagerSect\">"
        item_pattern = "<div%s+class=\"searchAccuracyMeasurement\".-あす楽締切時間を表示.-</div>"
        link_pattern = "<div%s+class=\"rsrSResultItemTxt\">.-<a%s+href=\"http://item.rakuten.co.jp/([^/]-)/([^/]-)/\">(.-)</a>"
        copy_txt_pattern = "<p%s+class=\"copyTxt\">(.-)</p>"
        review_num_pattern = "<span%s+class=\"txtIconReviewNum\">.-<a%s+href=\"http://review.rakuten.co.jp/.-\">(%d+)件"
        price_pattern = "<p%s+class=\"price\">.->([,0-9]+)<span>.-円</span>"
        point_pattern = "<p%s+class=\"point\">.-(%d+)倍</p>"

    end
    
    return sales_desc_pattern, item_desc_pattern, tbody_pattern, item_pattern, link_pattern, copy_txt_pattern, review_num_pattern, price_pattern, point_pattern
end

comp_rank = function (t1, t2)
    return t1.rank < t2.rank
end

get_related_keywords = function (is_mobile, keyword, encode_key)
    local t = {}
    local time = os.time()
    local response, code = http.request{url = string.format("http://api.dict.search.rakuten.co.jp/dictionary?sv=mall&fnc=each&h=10&rid=8648558079&sid=3&q=%s&oe=utf-8&of=js&cb=jsonp%s", encode_key, time), headers = fake_header(is_mobile), sink = ltn12.sink.table(t)}
    if code ~= 200 then
        return {}
    end
    
    local c = table.concat(t)
    local related_keys = {}    
    for key in string.gmatch(c, "\"(.-)\"") do
        if key ~= keyword then
            table.insert(related_keys, key)
        end
    end
    return related_keys
end

track_item_detail = function (is_mobile, shop_name, item_code, field)
    local t = {}
    local response, code = http.request{url = string.format("http://item.rakuten.co.jp/%s/%s", shop_name, item_code), headers = fake_header(is_mobile), sink = ltn12.sink.table(t)}
    if code ~= 200 then
        return 0
    end
    
    local c = table.concat(t)
    local err
    c, err = iconv.new("utf-8//IGNORE", "euc-jp"):iconv(c)
    if err then
        return err
    end
    local point = string.match(c, "a%.ichiba%.jp%.rakuten%-static%.com/com/inc/search/contents%-event/festival/img/search_icon/deal/deal.-\".-<span.->(%d+)") or 0
    local sales_desc = ""
    local item_desc = ""
    
    if field == nil then
        local sales_desc_pattern, item_desc_pattern = patterns(is_mobile)
        sales_desc = string.match(c, sales_desc_pattern)
        item_desc = string.match(c, item_desc_pattern)
    end
    
    return point, sales_desc, item_desc
end

run = function (params)
    local data = cjson.decode(params)
    local sales_desc_pattern, item_desc_pattern, tbody_pattern, item_pattern, link_pattern, copy_txt_pattern, review_num_pattern, price_pattern, point_pattern = patterns(data.is_mobile)
    local page_limit
    if data.is_mobile == "1" then
        page_limit = 10
    else
        page_limit = 45
    end
    
    local t = {}
    local response, code = http.request{url = string.format("http://search.rakuten.co.jp/search/mall/%s/-/p.1", data.keyword), headers = fake_header(data.is_mobile), sink = ltn12.sink.table(t)}
    local result = {}
    if code ~= 200 then
        return nil
    end
    
    local need_desc = data.need_desc
    result.is_mobile = data.is_mobile
    result.keyword_id = data.keyword_id
    result.keyword = data.keyword
    local date_table = os.date("*t")
    result.date = string.format("%4d-%02d-%02d", date_table.year, date_table.month, date_table.day)
    
    local c = table.concat(t)
    if data.is_mobile == "0" and data.page_num == "1" then
        result.related_keys = get_related_keywords(data.is_mobile, data.keyword, data.encode_key)
    end
    
    local tbody = string.match(c, tbody_pattern)
    if tbody == nil then
        return nil
    end

    local count = 0
    for tr in string.gmatch(tbody, item_pattern) do
        local item = {}
        
        count = count + 1
        if data.is_mobile == "1" then
            item.rank = page_limit * (data.page_num - 1) + count
        else
            local item_pos, page_num = string.match(tr, "<div%s+class=\"searchAccuracyMeasurement\"%s+itemPosition=\"(%d+)\"%s+pageNumber=\"(%d+)\".-</div>")
            item.rank = page_limit * (page_num - 1) + item_pos
        end
        item.shop_name, item.item_code, item.title = string.match(tr, link_pattern)
        item.copy_txt = string.match(tr, copy_txt_pattern)
        item.review_num = string.match(tr, review_num_pattern)
        item.price = string.gsub(string.match(tr, price_pattern), ",", "")
        item.point = string.match(tr, point_pattern) or 0
        if need_desc == "1" then
            local tmp_point = 0
            tmp_point, item.sales_desc, item.item_desc = track_item_detail(data.is_mobile, item.shop_name, item.item_code)
            if item.point == 0 and tmp_point > 0 then
                item.point = tmp_point
            end
        end
        
        if string.match(tr, "<div%s+class=\"superDeal\">") then
            item.is_super_deal = 1
        end
        if string.match(tr, "送料込") then
            item.free_shipping = 1
        end
        table.insert(result, item)
    end
    table.sort(result, comp_rank)
    
    if need_desc == "0" then
        for k,v in ipairs(result) do
            if v.is_super_deal then
                v.point = track_item_detail(data.is_mobile, v.shop_name, v.item_code, "point")
            end
        end
    end
    
    return cjson.encode({result = result})
end

print(run('{"is_mobile":"0","keyword":"天然ダイヤ","encode_key":"%E5%A4%A9%E7%84%B6%E3%83%80%E3%82%A4%E3%83%A4","keyword_id":"111111","page_num":"1","need_desc":"1"}'))
