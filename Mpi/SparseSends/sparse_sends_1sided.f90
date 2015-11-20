program sparse_sends
use, intrinsic :: iso_fortran_env, only : dp => REAL64, sp => REAL32
use mpi_f08
implicit none
integer :: rank, size, incr, i, msg_buff, n, iter, nr_iters
integer, asynchronous :: nr_recvs
type(MPI_Win) :: window
integer :: disp_unit
integer(kind=MPI_ADDRESS_KIND) :: integer_size, lb, recv_buff_size, &
                                  target_disp
integer, dimension(:), allocatable :: seed                                  
integer, parameter :: tag = 17, target_rank = 0
real(kind=sp) :: r, prob
logical :: will_send
type(MPI_Status) :: status

! setup MPI and determine rank & size
call MPI_init()
call MPI_Comm_size(MPI_COMM_WORLD, size)
call MPI_Comm_rank(MPI_COMM_WORLD, rank)

! seed random number generator, this is a really, really bad method,
! don't do this at home!
call random_seed(size = n)
allocate(seed(n))
do i = 1, n
    seed(i) = (rank + i)*17 + i*253 + i**2*9193*rank**2
end do
call random_seed(put=seed)

! initialize send probabiltiy, on average, prob*(size - 1) processes will
! send, as well as the number of iterations
prob = 0.5
nr_iters = 3

! compute the size of the receive buffer in bytes, as well as the
! displacement units in bytes.
call MPI_Type_get_extent(MPI_INTEGER, lb, integer_size)
recv_buff_size = 1*integer_size
disp_unit = integer_size

! create a window for one-sided communication, nr_recvs acts as the
! receive buffer
call MPI_Win_create(nr_recvs, recv_buff_size, disp_unit, MPI_INFO_NULL, &
                    MPI_COMM_WORLD, window)

do iter = 1, nr_iters
    if (rank == 0) &
        nr_recvs = 0

    ! start RMA epoch, only processes intending to send add 1 to nr_recvs
    if (.not. MPI_ASYNC_PROTECTS_NONBLOCKING) &
        call MPI_F_SYNC_REG(nr_recvs)
    if (rank == 0) then
        call MPI_Win_fence(MPI_MODE_NOPRECEDE, window)
    else
        call MPI_Win_fence(MPI_MODE_NOPRECEDE + MPI_MODE_NOSTORE + &
                           MPI_MODE_NOPUT, window)
    end if
    if (rank /= target_rank) then
        call random_number(r)
        will_send = r < prob 
        if (will_send) then
            print '(A, I0)', 'will send: ', rank
            incr = 1
            target_disp = 0
            call MPI_Accumulate(incr, 1, MPI_INTEGER, target_rank, &
                                target_disp, 1, MPI_INTEGER, &
                                MPI_SUM, window)
        end if
    end if
    call MPI_Win_fence(MPI_MODE_NOSUCCEED + MPI_MODE_NOPUT + &
                       MPI_MODE_NOSTORE, window)
    if (.not. MPI_ASYNC_PROTECTS_NONBLOCKING) &
        call MPI_F_SYNC_REG(nr_recvs)

    ! for debugging, print the number of senders
    if (rank == target_rank) then
        print '(A, I0)', 'expecting ', nr_recvs
    end if

    ! the target will receive nr_recvs messages, each process willing
    ! to send sends 1
    if (rank == target_rank) then
        do i = 1, nr_recvs
            call MPI_Recv(msg_buff, 1, MPI_INTEGER, MPI_ANY_SOURCE, tag, &
                          MPI_COMM_WORLD, status)
            print '(A, I0)', 'received from ', status%MPI_SOURCE
        end do
    else
        if (will_send) then
            call MPI_Send(rank, 1, MPI_INTEGER, target_rank, tag, &
                          MPI_COMM_WORLD)
        end if
    end if
end do

! finalize MPI
call MPI_Finalize()

end program sparse_sends