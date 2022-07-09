@devicecommand function update(rp::RedPitayaDAQ, tag::String)
  update!(rp, tag)
  return nothing
end

@devicecommand function update(rp::RedPitayaDAQ)
  options = listReleaseTags()
  menu = TerminalMenus.RadioMenu(options, pagesize=4)

  choice = TerminalMenus.request("Please choose the release tag for the update:", menu)

  if choice != -1
    update!(rp, options[choice])
  else
    println("Update canceled.")
  end
  
  return nothing
end