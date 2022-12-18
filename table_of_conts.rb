def idize(txt)
  txt.downcase.gsub(/\s/, '-').gsub(/[^a-z\-]/, '')
end

lines = File.open('vknotes.html', 'r', &:read).lines.map(&:strip)

header_fmt = /^<h([1-6])>(.+)<\/h[1-6]>$/

table_of_conts_ndx = 0

headers = []
lines.each_with_index do |l,i|
  if header_fmt =~ l
    lvl = $~[1]
    txt = $~[2]

    headers << [l, i, lvl.to_i, txt]

    if l.include? 'Table of contents'
      table_of_conts_ndx = i
    end

    lines[i] = "<h#{lvl} id='#{idize(txt)}'>#{txt}</h#{lvl}>"
  end
end

table_of_conts = "<ul>\n"

cur_hdr = 2
headers.each do |line, ndx, lvl, txt|
  unless line.include?('Vulkan notes') || line.include?('Table of contents')
    while lvl > cur_hdr
      table_of_conts << "#{' '*cur_hdr}<ul>\n"
      cur_hdr += 1
    end

    while lvl < cur_hdr
      table_of_conts << "#{' '*cur_hdr}</ul>\n"
      cur_hdr -= 1
    end

    table_of_conts << "#{' '*cur_hdr}<li><a href='##{idize(txt)}'>#{txt}</a></li>\n"
  end
end

while cur_hdr >= 2
  table_of_conts << "</ul>\n"
  cur_hdr -= 1
end

lines.insert(table_of_conts_ndx + 1, *(table_of_conts.lines.map(&:strip)))

puts lines.join("\n")
