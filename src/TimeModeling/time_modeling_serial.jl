
export time_modeling

# Setup time-domain linear or nonlinear foward and adjoint modeling and interface to devito
function time_modeling(model_full::Model, srcGeometry, srcData, recGeometry, recData, dm, srcnum::Int64, op::Char, mode::Int64, options)

    # Load full geometry for out-of-core geometry containers
    typeof(recGeometry) == GeometryOOC && (recGeometry = Geometry(recGeometry))
    typeof(srcGeometry) == GeometryOOC && (srcGeometry = Geometry(srcGeometry))

    # limit model to area with sources/receivers
    if options.limit_m == true
        model = deepcopy(model_full)
        if op=='J' && mode==1
            model, dm = limit_model_to_receiver_area(srcGeometry,recGeometry,model,options.buffer_size;pert=dm)
        else
            model = limit_model_to_receiver_area(srcGeometry,recGeometry,model,options.buffer_size)
        end
    else
        model = model_full
    end

    # Set up Python model structure
    modelPy = devito_model(model, options)
    if op=='J' && mode == 1
        update_dm(modelPy, dm, options)
        modelPy.dm == 0 && return judiVector(recGeometry, zeros(Float32, recGeometry.nt[1], length(recGeometry.xloc[1])))
    end

    # Load shot record if stored on disk
    if recData != nothing
        if typeof(recData[1]) == SegyIO.SeisCon
            recDataCell = Array{Array}(undef, 1); recDataCell[1] = convert(Array{Float32,2},recData[1][1].data); recData = recDataCell
        elseif typeof(recData[1]) == String
            recData = load(recData[1])."d".data
        end
    end

    # Remove receivers outside the modeling domain (otherwise leads to segmentation faults)
    if mode==1 && recGeometry != nothing
        recGeometry = remove_out_of_bounds_receivers(recGeometry, model)
    elseif mode==-1 && recGeometry != nothing
        recGeometry, recData = remove_out_of_bounds_receivers(recGeometry, recData, model)
    end

    # Devito interface
    argout = devito_interface(modelPy, model, srcGeometry, srcData, recGeometry, recData, dm, options)

    # Extend gradient back to original model size
    if op=='J' && mode==-1 && options.limit_m==true
        argout = PhysicalParameter(extend_gradient(model_full, model, argout), model.d, model.o)
    end

    return argout
end

# Function instance without options
time_modeling(model::Model, srcGeometry::Geometry, srcData, recGeometry::Geometry, recData, perturbation, srcnum::Int64, op::Char, mode::Int64) =
    time_modeling(model, srcGeometry, srcData, recGeometry, recData, perturbation, srcnum, op, mode, Options())
