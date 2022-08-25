const calibration_file = raw"C:\Users\mtarc\OneDrive - The University of Akron\Data\Calibrations\photon_lookup.xlsx"


"""
    photon_lookup(wavelength, nd, percent, stim_time, calibration_file[,sheet_name])

Uses the calibration file or datasheet to look up the photon density. The Photon datasheet should be either 
"""
function photon_lookup(wavelength::Real, nd::Real, percent::Real, calibration_file::String, sheet_name::String="Current_Test")
     df = DataFrame(XLSX.readtable(calibration_file, sheet_name)...)
     Qi = df |>
          @filter(_.Wavelength == wavelength) |>
          @filter(_.ND == nd) |>
          @filter(_.Intensity == percent) |>
          #@filter(_.stim_time == stim_time) |>
          @map(_.Photons) |>
          DataFrame
     #%%
     if size(Qi, 1) != 0
          #Only return f an entry exists
          return Qi.value[1]
     end
end

#========================================================================================================================================

These functions extract the file information from the datafile path

========================================================================================================================================#

"""
Lets shift to using Regex to extract file information
"""
function DataPathExtraction(path::String, calibration_file::String;
     verbose=false,
     extract_photons=true
)
     #The last line of the string should be the nd information
     if verbose
          println(path)
     end
     path_array = splitpath(path) #first we can split the file path into seperate strings
     nt = (Path=path,)
     date_info = findmatch(path_array, date_regex; verbose=verbose)
     if !isnothing(date_info)
          nt = merge(nt, date_info)
     end

     animal_info = findmatch(path_array, animal_regex; verbose=verbose)
     if !isnothing(animal_info)
          #try to match the age Regex
          nt_keys = keys(animal_info)
          nt_vals = [values(animal_info)...]
          idx = findall(nt_keys .== :Age)[1]
          if nt_vals[idx] == "Adult"
               nt_vals[idx] = "30"
          else
               nt_vals[idx] = filter_string(Int64, nt_vals[idx])
          end
          #convert values like "P8" to 8, and Adult to 30

          animal_info = NamedTuple{nt_keys}(nt_vals)
          nt = merge(nt, animal_info)
     end

     #now lets look for a condition in the possible conds
     cond = find_condition(path_array; possible_conds=["BaCl", "BaCl_LAP4", "NoDrugs"])
     nt = merge(nt, (Condition=cond,))

     pc = find_condition(path_array; possible_conds=["Rods", "Cones"])
     if !isnothing(pc)
          nt = merge(nt, (Photoreceptor=pc,))
     else
          nt = merge(nt, (Photoreceptor="Rods",))
     end

     wv = find_condition(path_array; possible_conds=["365", "365UV", "520", "520Green", "525", "525Green"])
     if !isnothing(wv)
          wv_value = filter_string(Int64, wv)
          if wv_value == "525" #This is a file error
               println("Old file name made a mistake")
               nt = merge(nt, (Wavelength="520",))
          else
               nt = merge(nt, (Wavelength=wv_value,))
          end
     elseif any(path_array .== "UV")
          nt = merge(nt, (Wavelength="365",))
     elseif any(path_array .== "Green") || nt.Photoreceptor == "Rods"
          nt = merge(nt, (Wavelength="520",))
     end

     intensity_info = findmatch(path_array, nd_file_regex; verbose=verbose) #find and extract the intensity info
     if !isnothing(intensity_info)
          nt = merge(nt, intensity_info)
          if extract_photons
               #extract the stimulus from the data
               stim_timestamps = extract_stimulus(path)[1].timestamps
               stim_time = round(Int64, (stim_timestamps[2] - stim_timestamps[1]) * 1000)
               #println(stim_time)
               nt = merge(nt, (Stim_Time=stim_time,))
               #now lets extract photons
               #println(nt.Wavelength)
               #println(intensity_info.ND)
               #println(intensity_info.Percent)
               photons = photon_lookup(
                    parse(Int64, nt.Wavelength),
                    parse(Int64, intensity_info.ND),
                    parse(Int64, intensity_info.Percent),
                    calibration_file
               ) .* stim_time
               nt = merge(nt, (Photons=photons,))
          end
          #now we can look for any date info
     end

     #return nt |> clean_nt_numbers
     return nt |> parseNamedTuple
end

DataPathExtraction(path::String; kwargs...) = DataPathExtraction(path, calibration_file; kwargs...)

"""
This function creates a new datasheet
"""
function createDatasheet(all_files::Vector{String})
     dataframe = DataFrame()
     for (idx, file) in enumerate(all_files)
          println("Analyzing file $idx of $(size(all_files, 1)): $file")
          entry = DataPathExtraction(file)
          if isnothing(entry) #Throw this in the case that the entry cannot be fit
               println(entry)
          else
               push!(dataframe, entry)
          end
     end
     
     dataframe
end

"""
This function opens an old datasheet
"""
function openDatasheet(data_file::String; sheetName::String = "All_Files", typeConvert = true)
     xf = readxlsx(data_file)
     if sheetName == "all"
          sheetnames = XLSX.sheetnames(xf)
          df_set = Dict(map(sn -> (sn => openDatasheet(data_file, sheetName = sn)), sheetnames))
          return df_set
     else
          s = xf[sheetName]
          df = XLSX.eachtablerow(s) |> DataFrame
          #We can walk through and try to convert each row to either an integer, Float, or String
          if typeConvert
               df = mapcols(x -> convert.(x[1] |> typeof, x), df) #This converts the categories to a type in the first position
          end
          return df
     end
end

"""
This function will read and update the datasheet with the new files
"""
function updateDatasheet(data_file::String, all_files::Vector{String}; reset::Bool = false, 
     savefile::Bool = true
)
     if reset
          #If this is selected, completely reset the analysis
     else
          df = openDatasheet(data_file) #First, open the old datasheet
          println("Searching for files that need to be added and removed")
          old_files = df[:,:Path] #Pull out a list of old files 
                    
          #This searches for files that occur in all files, but not in old files, indicating they need added to the analysis
          files_to_add = findall(isnothing, indexin(all_files, old_files))

          #This searches for files that are in old files, but not not in all files, indicating they may need deleted
          files_to_remove = findall(isnothing, indexin(old_files, all_files))
          
          duplicate_files = findall(nonunique(df))
          
          if !isempty(files_to_add) #There are no files to add
               println("Adding $(length(files_to_add)) files")
               new_files = all_files[files_to_add] 
               df_new = createDatasheet(new_files) 
               df = vcat(df, df_new) #Add the new datasheet to the old one
          end

          if !isempty(files_to_remove)
               println("Removing $(length(files_to_add)) files")
               deleteat!(df, files_to_remove)
          end

          if !isempty(duplicate_files)
               println("Removing $(length(duplicate_files)) duplicated files")
               deleteat!(df, duplicate_files)
          end

          #Sort the dataframe
          df = df |>
               @orderby(_.Year) |> @thenby(_.Month) |> @thenby(_.Date) |>
               @thenby(_.Animal) |> @thenby(_.Genotype) |> @thenby(_.Condition) |>
               @thenby(_.Wavelength) |> @thenby(_.Photons) |>
          DataFrame
          
          if savefile
               print("Saving file... ")
               XLSX.openxlsx(data_file, mode="rw") do xf
                    try
                         sheet = xf["All_Files"] #Try opening the All_Files
                    catch
                         println("Adding sheets")
                         XLSX.addsheet!(xf, "All_Files")
                    end
                    XLSX.writetable!(xf["All_Files"],
                         collect(DataFrames.eachcol(df)),
                         DataFrames.names(df))
               end
               println("Complete")
          end

          return df
     end
end



#==========================================================================================
These functions can open data from the dataframes
==========================================================================================#

"""
This code is actually an extension of the ABFReader package and somewhat specific for my own needs.
     I will be some way of making this more general later

"""
function readABF(df::DataFrame; extra_channels=nothing, a_name="A_Path", ab_name="AB_Path", kwargs...)
     df_names = names(df)
     #Check to make sure path is in the dataframe
     #Check to make sure the dataframe contains channel info
     @assert "Channel" ∈ df_names
     if (a_name ∈ df_names) #&& ("AB_Path" ∈ df_names) #This is a B subtraction
          #println("B wave subtraction")
          A_paths = string.(df.A_Path)
          AB_paths = string.(df.Path)
          ch = (df.Channel |> unique) .|> String
          if !isnothing(extra_channels)
               ch = (vcat(ch..., extra_channels...))
          end
          A_data = readABF(A_paths; channels=ch, kwargs...)
          AB_data = readABF(AB_paths; channels=ch, kwargs...)
          return A_data, AB_data
     elseif (ab_name ∈ df_names) #&& ("ABG_Path" ∈ df_names) #This is the G-wave subtraction
          #println("G wave subtraction")
          AB_paths = string.(df.AB_Path)
          ABG_paths = string.(df.Path)
          ch = (df.Channel |> unique) .|> String
          if !isnothing(extra_channels)
               ch = (vcat(ch..., extra_channels...))
          end
          AB_data = readABF(AB_paths, channels=ch, kwargs...)
          ABG_data = readABF(ABG_paths, channels=ch, kwargs...)

          return AB_data, ABG_data
     elseif ("Path" ∈ df_names) #This is just the A-wave
          paths = string.(df.Path)
          ch = (df.Channel |> unique) .|> String
          if !isnothing(extra_channels)
               ch = (vcat(ch..., extra_channels...))
          end
          data = readABF(paths, channels=ch, kwargs...)
          return data
     else
          throw("There is no path key")
     end


end

readABF(df_row::DataFrameRow; kwargs...) = readABF(df_row |> DataFrame; kwargs...)