
extended_source_modeling(model::Model, srcData, recGeometry, recData, weights, perturbation, srcnum::UnitRange{Int64}, op::Char, mode::Int64) =
    extended_source_modeling(model, srcData, recGeometry, recData, weights, perturbation, srcnum, op, mode, Options())

function extended_source_modeling(model::Model, srcData, recGeometry, recData, weights, perturbation, srcnum::UnitRange{Int64}, op::Char, mode::Int64, options)
# extended_source_modeling function for multiple sources. Depending on the operator and mode, this function distributes the sources
# and if applicable the input data amongst the available workers.

    p = default_worker_pool()
    extended_source_modeling_par = remote(TimeModeling.extended_source_modeling)
    extended_source_modeling = retry(extended_source_modeling_par)

    numSources = length(srcnum)
    results = Array{Any}(undef, numSources)

    if !isnothing(weights) && typeof(weights) != Array{Array, 1}
        weights = convert_to_cell_array(weights)
    end
    if !isnothing(recData) && typeof(recData) != Array{Array, 1}
        recData = convert_to_cell_array(recData)
    end

    # Process shots from source channel asynchronously
    @sync begin
        for j=1:numSources

            # local receiver geometry for current position
            if recGeometry == nothing
                recGeometryLocal = nothing
            else
                recGeometryLocal = subsample(recGeometry,j)
            end
            opt_local = subsample(options,j)
            numSources > 1 && (opt_local.save_wavefield_to_disk=true)    # don't collect wavefields on master

            # Parallelization
            if op=='F' && mode==1
                @async results[j] = extended_source_modeling(model, copy(srcData[j:j]), recGeometryLocal, nothing, copy(weights[j:j]), nothing, j, op, mode, opt_local)
            elseif op=='F' && mode==-1
                @async results[j] = extended_source_modeling(model, copy(srcData[j:j]), recGeometryLocal, copy(recData[j:j]), nothing, nothing, j, op, mode, opt_local)
            elseif op=='J' && mode==1
                @async results[j] = extended_source_modeling(model, copy(srcData[j:j]), recGeometryLocal, nothing, copy(weights[j:j]), perturbation, j, op, mode, opt_local)
            elseif op=='J' && mode==-1
                @async results[j] = extended_source_modeling(model, copy(srcData[j:j]), recGeometryLocal, copy(recData[j:j]), copy(weights[j:j]), nothing, j, op, mode, opt_local)
            end
        end
    end

    if op=='F' || (op=='J' && mode==1)
        argout1 = results[1]
        for j=2:numSources
            argout1 = [argout1; results[j]]
        end
    elseif op=='J' && mode==-1
        argout1 = results[1]
        for j=2:numSources
            argout1 += results[j]
        end
    else
        error("operation no defined")
    end
    return argout1
end
