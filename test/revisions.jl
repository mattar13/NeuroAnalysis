using Revise
using ElectroPhysiology, PhysiologyAnalysis
using Pkg; Pkg.activate("test")
using GLMakie, PhysiologyPlotting

#%% We want to make several convienance functions so we can run everything
include(raw"C:\Users\mtarc\.julia\dev\PhysiologyAnalysis\src\Analysis\ImagingAnalysis\CellPose_port.jl")

model = cellpose_model()

#╔═╡Point to the filename
data2P_fn = raw"G:\Data\Calcium Imaging\2024_07_24_OPN4_P9\ca_img4004.tif"

#╔═╡Extract the image
domain_x = (xmin, xmax) = (0.0, 0.350)
domain_y = (ymin, ymax) = (0.0, 0.350)
data2P = readImage(data2P_fn);	
deinterleave!(data2P) #This seperates the movies into two seperate movies

#╔═╡Seperate the red and green channels
img_arr = get_all_frames(data2P)
xlims = LinRange(ymin, xmax, size(img_arr,1))
ylims = LinRange(ymin, ymax, size(img_arr,2))

grn_zproj = project(data2P, dims = (3))[:,:,1,1]
red_zproj = project(data2P, dims = (3))[:,:,1,2]


#%% ╔═╡Plot the figure
fig = Figure(figsize = (1000, 500))
ax1 = GLMakie.Axis(fig[1,1], title = "Green Channel", aspect = 1.0)
ax2 = GLMakie.Axis(fig[1,2], title = "Mask Channel", aspect = 1.0)

hm1 = heatmap!(ax1, xlims, ylims, grn_zproj, colormap = :viridis, colorrange = (0.0, maximum(grn_zproj)/25))
hm2 = heatmap!(ax2, xlims, ylims, mask, colormap = :viridis)

fig